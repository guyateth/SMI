#include <mpi.h>
#include <stdlib.h>
#include <cmath>
#include <iostream>
#include <numeric>
#include <sstream>
#include <vector>
#include "common.h"
#include "hlslib/intel/OpenCL.h"
#include "stencil.h"

// Convert from C to C++
using Data_t = DTYPE;
constexpr Data_t kBoundary = BOUNDARY_VALUE;
constexpr int kX = X;
constexpr int kY = Y;
constexpr int kPX = PX;
constexpr int kPY = PY;
constexpr int kXLocal = kX / kPX;
constexpr int kYLocal = kY / kPY;
constexpr auto kUsage =
    "Usage: ./stencil_smi <[emulator/hardware]> <num timesteps>\n";

using AlignedVec_t =
    std::vector<Data_t, hlslib::ocl::AlignedAllocator<Data_t, 64>>;

// Reference implementation for checking correctness
void Reference(AlignedVec_t &domain, const int timesteps) {
  AlignedVec_t buffer(domain);
  for (int t = 0; t < timesteps; ++t) {
    for (int i = 1; i < kX - 1; ++i) {
      for (int j = 1; j < kY - 1; ++j) {
        buffer[i * kY + j] =
            static_cast<Data_t>(0.25) *
            (domain[(i - 1) * kY + j] + domain[(i + 1) * kY + j] +
             domain[i * kY + j - 1] + domain[i * kY + j + 1]);
      }
    }
    domain.swap(buffer);
  }
}

std::vector<AlignedVec_t> SplitMemory(AlignedVec_t const &memory) {
  std::vector<AlignedVec_t> split(kPX * kPY,
                                  AlignedVec_t((kXLocal) * (kYLocal)));
  for (int px = 0; px < kPX; ++px) {
    for (int py = 0; py < kPY; ++py) {
      for (int x = 0; x < kXLocal; ++x) {
        for (int y = 0; y < kYLocal; ++y) {
          split[px * kPY + py][x * kYLocal + y] =
              memory[px * kXLocal * kY + x * kY + py * kYLocal + y];
        }
      }
    }
  }
  return split;
}

AlignedVec_t CombineMemory(std::vector<AlignedVec_t> const &split) {
  AlignedVec_t memory(kX * kY);
  for (int px = 0; px < kPX; ++px) {
    for (int py = 0; py < kPY; ++py) {
      for (int x = 0; x < kXLocal; ++x) {
        for (int y = 0; y < kYLocal; ++y) {
          memory[px * kXLocal * kY + x * kY + py * kYLocal + y] =
              split[px * kPY + py][x * kYLocal + y];
        }
      }
    }
  }
  return memory;
}

void _MPIStatus(std::stringstream &) {}

template <typename T, typename... Ts>
void _MPIStatus(std::stringstream &ss, T &&arg, Ts &&... args) {
  ss << arg;
  _MPIStatus(ss, args...);
}

template <typename T, typename... Ts>
void MPIStatus(int rank, T &&arg, Ts... args) {
  std::stringstream ss;
  ss << "[" << rank << "] " << arg;
  _MPIStatus(ss, args...);
  std::cout << ss.str() << std::flush;
}

int main(int argc, char **argv) {
  MPI_Init(&argc, &argv);

  int mpi_size, mpi_rank;
  MPI_Comm_size(MPI_COMM_WORLD, &mpi_size);
  MPI_Comm_rank(MPI_COMM_WORLD, &mpi_rank);
  const int i_px = mpi_rank / kPY;
  const int i_py = mpi_rank % kPY;

  // Handle input arguments
  if (argc != 3) {
    std::cout << kUsage;
    return 1;
  }
  bool emulator = false;
  std::string mode_str(argv[1]);
  std::string kernel_path;
  if (mode_str == "emulator") {
    setenv("CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA", "1", false);
    emulator = true;
    // In emulation mode, each rank has its own kernel file
    kernel_path =
        ("stencil_smi_emulator_" + std::to_string(mpi_rank) + ".aocx");
  } else if (mode_str == "hardware") {
    kernel_path = "stencil_smi_hardware.aocx";
    emulator = false;
  } else {
    std::cout << kUsage;
    return 2;
  }

  const int timesteps = std::stoi(argv[2]);

  // Read routing tables
  std::vector<std::vector<char>> routing_tables_ckr(
      kChannelsPerRank, std::vector<char>(4));
  std::vector<std::vector<char>> routing_tables_cks(
      kChannelsPerRank, std::vector<char>(mpi_size));
  for (int i = 0; i < kChannelsPerRank; ++i) {
    LoadRoutingTable<char>(mpi_rank, i, 4, "stencil_smi_routing", "ckr",
                           &routing_tables_ckr[i][0]);
    LoadRoutingTable<char>(mpi_rank, i, mpi_size, "stencil_smi_routing", "cks",
                           &routing_tables_cks[i][0]);
  }

  std::vector<AlignedVec_t> host_buffers;
  AlignedVec_t host_buffer, reference;
  if (mpi_rank == 0) {
    MPIStatus(mpi_rank, "Initializing host memory...\n");
    // Set center to 0
    reference = AlignedVec_t(kX * kY, 0);
    // Set boundaries to 1
    for (int i = 0; i < kY; ++i) {
      reference[i] = 1;
      reference[kY * (kX - 1) + i] = 1;
    }
    for (int i = 0; i < kX; ++i) {
      reference[i * kY] = 1;
      reference[i * kY + kY - 1] = 1;
    }
    host_buffers = SplitMemory(reference);
    host_buffer = std::move(host_buffers[0]);
    MPIStatus(mpi_rank, "Communicating host memory...\n");
    for (int i = 1; i < mpi_size; ++i) {
      MPI_Send(host_buffers[i].data(), host_buffers[i].size(), MPI_FLOAT, i, 0,
               MPI_COMM_WORLD);
    }
  } else {
    MPIStatus(mpi_rank, "Communicating host memory...\n");
    host_buffer = AlignedVec_t(kXLocal * kYLocal);
    MPI_Status status;
    MPI_Recv(host_buffer.data(), host_buffer.size(), MPI_FLOAT, 0, 0,
             MPI_COMM_WORLD, &status);
  }

  MPIStatus(mpi_rank, "Creating OpenCL context...\n");
  hlslib::ocl::Context context;

  MPIStatus(mpi_rank, "Allocating device memory...\n");
  auto device_buffer =
      context.MakeBuffer<Data_t, hlslib::ocl::Access::readWrite>(2 * kXLocal *
                                                                 kYLocal);
  std::vector<hlslib::ocl::Buffer<char, hlslib::ocl::Access::read>>
      routing_tables_cks_device(kChannelsPerRank);
  std::vector<hlslib::ocl::Buffer<char, hlslib::ocl::Access::read>>
      routing_tables_ckr_device(kChannelsPerRank);
  for (int i = 0; i < kChannelsPerRank; ++i) {
    routing_tables_cks_device[i] =
        context.MakeBuffer<char, hlslib::ocl::Access::read>(
            routing_tables_cks[i].cbegin(), routing_tables_cks[i].cend());
    routing_tables_ckr_device[i] =
        context.MakeBuffer<char, hlslib::ocl::Access::read>(
            routing_tables_ckr[i].cbegin(), routing_tables_ckr[i].cend());
  }

  MPIStatus(mpi_rank, "Creating program from binary...\n");
  auto program = context.MakeProgram(kernel_path);

  // std::pair<kernel object, whether kernel is autorun>
  std::vector<hlslib::ocl::Kernel> comm_kernels;

  MPIStatus(mpi_rank, "Starting communication kernels...\n");
  for (int i = 0; i < kChannelsPerRank; ++i) {
    comm_kernels.emplace_back(program.MakeKernel("CK_S_" + std::to_string(i),
                                                 routing_tables_cks_device[i]));
    comm_kernels.emplace_back(program.MakeKernel("CK_R_" + std::to_string(i),
                                                 routing_tables_ckr_device[i],
                                                 char(mpi_rank)));
  }
  for (auto &k : comm_kernels) {
    // Will never terminate, so we don't care about the return value of fork
    k.ExecuteTaskFork();
  }

  // Wait for communication kernels to start
  MPI_Barrier(MPI_COMM_WORLD);

  MPIStatus(mpi_rank, "Starting memory conversion kernels...\n");
  std::vector<hlslib::ocl::Kernel> conv_kernels;
  conv_kernels.emplace_back(
      program.MakeKernel("ConvertReceiveLeft", i_px, i_py));
  conv_kernels.emplace_back(
      program.MakeKernel("ConvertReceiveRight", i_px, i_py));
  conv_kernels.emplace_back(
      program.MakeKernel("ConvertReceiveTop", i_px, i_py));
  conv_kernels.emplace_back(
      program.MakeKernel("ConvertReceiveBottom", i_px, i_py));
  conv_kernels.emplace_back(program.MakeKernel("ConvertSendLeft", i_px, i_py));
  conv_kernels.emplace_back(program.MakeKernel("ConvertSendRight", i_px, i_py));
  conv_kernels.emplace_back(program.MakeKernel("ConvertSendTop", i_px, i_py));
  conv_kernels.emplace_back(
      program.MakeKernel("ConvertSendBottom", i_px, i_py));
  conv_kernels.emplace_back(
      program.MakeKernel("ConvertSendBottom", i_px, i_py));
  for (auto &k : conv_kernels) {
    k.ExecuteTaskFork();
  }

  // Wait for conversion kernels to start
  MPI_Barrier(MPI_COMM_WORLD);

  MPIStatus(mpi_rank, "Creating compute kernels...\n");
  std::vector<hlslib::ocl::Kernel> compute_kernels;
  compute_kernels.emplace_back(
      program.MakeKernel("Read", device_buffer, i_px, i_py, timesteps));
  compute_kernels.emplace_back(
      program.MakeKernel("Stencil", i_px, i_py, timesteps));
  compute_kernels.emplace_back(
      program.MakeKernel("Write", device_buffer, i_px, i_py, timesteps));

  MPIStatus(mpi_rank, "Copying data to device...\n");
  device_buffer.CopyFromHost(0, kXLocal * kYLocal, host_buffer.cbegin());
  device_buffer.CopyFromHost(kXLocal * kYLocal, kXLocal * kYLocal,
                             host_buffer.cbegin());

  // Wait for all ranks to be ready for launch 
  MPI_Barrier(MPI_COMM_WORLD);

  MPIStatus(mpi_rank, "Launching kernels...\n");
  std::vector<std::future<std::pair<double, double>>> futures;
  const auto start = std::chrono::high_resolution_clock::now();
  for (auto &k : compute_kernels) {
    futures.emplace_back(k.ExecuteTaskAsync());
  }

  MPIStatus(mpi_rank, "Waiting for kernels to finish...\n");
  for (auto &f : futures) {
    f.wait();
  }
  const auto end = std::chrono::high_resolution_clock::now();
  const double elapsed =
      1e-9 *
      std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
  MPIStatus(mpi_rank, "Finished in ", elapsed, " seconds.\n");

  // Make sure all kernels finished 
  MPI_Barrier(MPI_COMM_WORLD);
  if (mpi_rank == 0) {
    const auto end_global = std::chrono::high_resolution_clock::now();
    const double elapsed =
        1e-9 *
        std::chrono::duration_cast<std::chrono::nanoseconds>(end_global - start)
            .count();
    MPIStatus(mpi_rank, "All ranks done in ", elapsed, " seconds.\n");
  }

  // Copy back result
  MPIStatus(mpi_rank, "Copying back result...\n");
  int offset = (timesteps % 2 == 0) ? 0 : kYLocal * kXLocal;
  device_buffer.CopyToHost(offset, kYLocal * kXLocal, host_buffer.begin());

  // Communicate
  MPIStatus(mpi_rank, "Communicating result...\n");
  if (mpi_rank == 0) {
    host_buffers[0] = std::move(host_buffer);
    for (int i = 1; i < mpi_size; ++i) {
      MPI_Status status;
      MPI_Recv(host_buffers[i].data(), host_buffers[i].size(), MPI_FLOAT, i, 0,
               MPI_COMM_WORLD, &status);
    }
  } else {
    MPI_Send(host_buffer.data(), host_buffer.size(), MPI_FLOAT, 0, 0,
             MPI_COMM_WORLD);
  }

  // Run reference implementation
  if (mpi_rank == 0) {
    MPIStatus(mpi_rank, "Running reference implementation...\n");
    Reference(reference, timesteps);

    const auto result = CombineMemory(host_buffers);

    // std::cout << "\n";
    // for (int i = 0; i < kX; ++i) {
    //   for (int j = 0; j < kY; ++j) {
    //     std::cout << result[i * kY + j] << " ";
    //   }
    //   std::cout << "\n";
    // }
    // std::cout << "\n";

    // Compare result
    const Data_t average =
        std::accumulate(reference.begin(), reference.end(), 0.0) /
        reference.size();
    for (int i = 0; i < kX; ++i) {
      for (int j = 0; j < kY; ++j) {
        const auto res = result[i * kY + j];
        const auto ref = reference[i * kY + j];
        if (std::abs(ref - res) >= 1e-4 * average) {
          std::cerr << "Mismatch found at (" << i << ", " << j << "): " << res
                    << " (should be " << ref << ").\n";
          return 3;
        }
      }
    }

    std::cout << "Successfully verified result.\n";
  }

  MPI_Finalize();

  return 0;
}