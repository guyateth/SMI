#include <cmath>
#include <iostream>
#include <numeric>
#include "hlslib/intel/OpenCL.h"
#include "stencil.h"

// Convert from C to C++
using Data_t = DTYPE;
constexpr int kX = X;
constexpr int kY = Y;
constexpr auto kUsage =
    "Usage: ./stencil_simple <[emulator/hardware]> <timesteps>\n";

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

int main(int argc, char **argv) {
  // Handle input arguments
  if (argc != 3) {
    std::cout << kUsage;
    return 1;
  }
  bool emulator = false;
  std::string mode_str(argv[1]);
  std::string kernel_path;
  if (mode_str == "emulator") {
    emulator = true;
    kernel_path = "stencil_simple_emulator.aocx";
  } else if (mode_str == "hardware") {
    kernel_path = "stencil_simple_hardware.aocx";
    emulator = false;
  } else {
    std::cout << kUsage;
    return 2;
  }

  const int timesteps = std::stoi(argv[2]);

  std::cout << "Initializing host memory...\n" << std::flush;
  // Set center to 0
  AlignedVec_t host_buffer(kY * kX, 0);
  // Set boundaries to 1
  for (int i = 0; i < kY; ++i) {
    host_buffer[i] = 1;
    host_buffer[kY * (kX - 1) + i] = 1;
  }
  for (int i = 0; i < kX; ++i) {
    host_buffer[i * kY] = 1;
    host_buffer[i * kY + kY - 1] = 1;
  }
  AlignedVec_t reference(host_buffer);

  // Create OpenCL kernels
  std::cout << "Creating OpenCL context...\n" << std::flush;
  hlslib::ocl::Context context;
  std::cout << "Allocating device memory...\n" << std::flush;
  auto device_buffer =
      context.MakeBuffer<Data_t, hlslib::ocl::Access::readWrite>(2 * kY * kX);
  std::cout << "Creating program from binary...\n" << std::flush;
  auto program = context.MakeProgram(kernel_path);
  std::cout << "Creating kernels...\n" << std::flush;
  std::vector<hlslib::ocl::Kernel> kernels;
  kernels.emplace_back(program.MakeKernel("Read", device_buffer, timesteps));
  kernels.emplace_back(program.MakeKernel("Stencil", timesteps));
  kernels.emplace_back(program.MakeKernel("Write", device_buffer, timesteps));
  std::cout << "Copying data to device...\n" << std::flush;
  // Copy to both sections of device memory, so that the boundary conditions
  // are reflected in both
  device_buffer.CopyFromHost(0, kY * kX, host_buffer.cbegin());
  device_buffer.CopyFromHost(kY * kX, kY * kX, host_buffer.cbegin());

  // Execute kernel
  std::cout << "Launching kernels...\n" << std::flush;
  std::vector<std::future<std::pair<double, double>>> futures;
  const auto start = std::chrono::high_resolution_clock::now();
  for (auto &k : kernels) {
    futures.emplace_back(k.ExecuteTaskAsync());
  }
  std::cout << "Waiting for kernels to finish...\n" << std::flush;
  for (auto &f : futures) {
    f.wait();
  }
  const auto end = std::chrono::high_resolution_clock::now();
  const double elapsed =
      1e-9 *
      std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
  std::cout << "Finished in " << elapsed << " seconds.\n" << std::flush;

  // Copy back result
  std::cout << "Copying back result...\n" << std::flush;
  int offset = (timesteps % 2 == 0) ? 0 : kX * kY;
  device_buffer.CopyToHost(offset, kX * kY, host_buffer.begin());

  // Run reference implementation
  std::cout << "Running reference implementation...\n" << std::flush;
  Reference(reference, timesteps);

  // Compare result
  const Data_t average =
      std::accumulate(reference.begin(), reference.end(), 0.0) /
      reference.size();
  for (int i = 0; i < kX; ++i) {
    for (int j = 0; j < kY; ++j) {
      const auto res = host_buffer[i * kY + j];
      const auto ref = reference[i * kY + j];
      if (std::abs(ref - res) >= 1e-4 * average) {
        std::cerr << "Mismatch found at (" << i << ", " << j << "): " << res
                  << " (should be " << ref << ").\n";
        return 3;
      }
    }
  }

  std::cout << "Successfully verified result.\n";

  return 0;
}
