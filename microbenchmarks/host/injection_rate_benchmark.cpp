/**
    Injection rate  benchmark
    A sender, push message of size 1 to a receiver.
    The average injection rate is computed.

    The FPGA program is written as MPMD with two programs, one for the sender
    and one for the receiver. The sender is rank 0, while the receiver can
    be any other rank between 1 and NUM_RANKS. For the intermediate ranks,
    the program for rank1 is loaded, in order to guarantee the routing
    of the transient channels.

 */

#include <stdio.h>
#include <string>
#include <iostream>
#include <fstream>
#include <unistd.h>
#include <cmath>
#include <utils/ocl_utils.hpp>
#include <utils/utils.hpp>
#include <hlslib/intel/OpenCL.h>
#include "smi_generated_host.c"
#define ROUTING_DIR "smi-routes/"

using namespace std;
int main(int argc, char *argv[])
{

    CHECK_MPI(MPI_Init(&argc, &argv));

    //command line argument parsing
    if(argc<9)
    {
        cerr << "Ingestion rate " <<endl;
        cerr << "Usage: "<< argv[0]<<"-m <emulator/hardware> -n <length> -r <rank on which run the receiver> -i <number of runs>  [-b <binary file>] "<<endl;
        exit(-1);
    }
    int n;
    int c;
    std::string program_path;
    int rank;
    bool emulator;
    char recv_rank;
    int fpga,runs;
    bool binary_file_provided=false;
    while ((c = getopt (argc, argv, "m:n:b:r:i:")) != -1)
        switch (c)
        {
            case 'n':
                n=atoi(optarg);
                break;
            case 'm':
            {
                std::string mode=std::string(optarg);
                if(mode!="emulator" && mode!="hardware")
                {
                    cerr << "Mode: emulator or hardware"<<endl;
                    exit(-1);
                }
                emulator=mode=="emulator";
                break;
            }
            case 'b':
                program_path=std::string(optarg);
                binary_file_provided=true;
                break;
            case 'i':
                runs=atoi(optarg);
                break;
            case 'r':
                recv_rank=atoi(optarg);
                if(recv_rank==0){
                    cerr <<  "Receiving rank can not be 0" <<endl;
                    exit(-1);
                }
                break;
            default:
                cerr << "Usage: "<< argv[0]<<"-m <emulator/hardware> -b <binary file> -n <length> -r <rank on which run the receiver> -i <number of runs> "<<endl;
                exit(-1);
        }

    cout << "Performing injection rate test with "<<n<<" elements"<<endl;
    int rank_count;
    CHECK_MPI(MPI_Comm_size(MPI_COMM_WORLD, &rank_count));
    CHECK_MPI(MPI_Comm_rank(MPI_COMM_WORLD, &rank));
    fpga = rank % 2; // which fpga to selects depends on the target cluster
    if(binary_file_provided)
    {
        if(!emulator)
        {
            if(rank==0)
                program_path = replace(program_path, "<rank>", std::string("0"));
            else //any rank other than 0
                program_path = replace(program_path, "<rank>", std::string("1"));
        }
        else//for emulation
        {
            program_path = replace(program_path, "<rank>", std::to_string(rank));
            if(rank==0)
                program_path = replace(program_path, "<type>", std::string("0"));
            else
                program_path = replace(program_path, "<type>", std::string("1"));
        }
    }
    else
    {
        if(emulator)
        {
            program_path = ("emulator_" + std::to_string(rank));
            if(rank==0) program_path+="/injection_rate_0.aocx";
            else program_path+="/injection_rate_1.aocx";
        }
        else
        {
            if(rank==0) program_path="injection_rate_0.aocx";
            else program_path="injection_rate_1.aocx";
        }

    }

    char hostname[256];
    gethostname(hostname, 256);
    std::cout << "Rank" << rank<<" executing on host:" <<hostname << " program: "<<program_path<<std::endl;

    hlslib::ocl::Context context(fpga);
    auto program = context.MakeProgram(program_path);
    std::vector<hlslib::ocl::Buffer<char, hlslib::ocl::Access::read>> buffers;
    SMI_Comm comm=SmiInit_injection_rate_0(rank, rank_count, ROUTING_DIR, context, program, buffers);

    //create kernel
    hlslib::ocl::Kernel app = (rank==0)?program.MakeKernel("app", n, recv_rank,  comm) : program.MakeKernel("app", n,comm) ;

    std::vector<double> times;
    for(int i=0;i<runs;i++)
    {
        CHECK_MPI(MPI_Barrier(MPI_COMM_WORLD));
        std::pair<double, double> timings;
        if(rank==0 || rank==recv_rank)
            timings = app.ExecuteTask();

        CHECK_MPI(MPI_Barrier(MPI_COMM_WORLD));
        if(rank==0)
            times.push_back(timings.first * 1e6);
    }

    if(rank==0)
    {   //compute means
        double mean=0;
        for(auto t:times)
            mean+=t;
        mean/=runs;
        //report the mean in usecs
        double stddev=0;
        for(auto t:times)
            stddev+=((t-mean)*(t-mean));
        stddev=sqrt(stddev/runs);
        double conf_interval_99=2.58*stddev/sqrt(runs);
        cout << "-------------------------------------------------------------------"<<std::endl;
        cout << "Injection time (usec): " << mean << " (sttdev: " << stddev<<")"<<endl;
        cout << "Conf interval 99: "<<conf_interval_99<<endl;
        cout << "Conf interval 99 within " <<(conf_interval_99/mean)*100<<"% from mean" <<endl;
        cout << "-------------------------------------------------------------------"<<std::endl;

        //save the info into output file
        std::ostringstream filename;
        filename << "injection_rate_" << n << ".dat";
        std::cout << "Saving info into: "<<filename.str()<<std::endl;
        ofstream fout(filename.str());
        fout << "#Ingestion rate benchnmark: sending  "<<n<<" messages of size 1" <<std::endl;
        fout << "#Average injection time (usecs): "<<mean<<endl;
        fout << "#Standard deviation (usecs): "<<stddev<<endl;
        fout << "#Confidence interval 99%: +- "<<conf_interval_99<<endl;
        fout << "#Execution times (usecs):"<<endl;
        for(auto t:times)
            fout << t << endl;
        fout.close();
    }
    CHECK_MPI(MPI_Finalize());

}
