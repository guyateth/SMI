# Download and unpack googletest at configure time

configure_file(${PROJECT_SOURCE_DIR}/CMakeGTEST.txt.in googletest-download/CMakeLists.txt)


execute_process(COMMAND ${CMAKE_COMMAND} -G "${CMAKE_GENERATOR}" .
  RESULT_VARIABLE result
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/googletest-download )
if(result)
  message(FATAL_ERROR "CMake step for googletest failed: ${result}")
endif()
execute_process(COMMAND ${CMAKE_COMMAND} --build .
  RESULT_VARIABLE result
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/googletest-download )
if(result)
  message(FATAL_ERROR "Build step for googletest failed: ${result}")
endif()

# Prevent overriding the parent project's compiler/linker
# settings on Windows
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)

# Add googletest directly to our build. This defines
# the gtest and gtest_main targets.
add_subdirectory(${CMAKE_CURRENT_BINARY_DIR}/googletest-src
                 ${CMAKE_CURRENT_BINARY_DIR}/googletest-build
                 EXCLUDE_FROM_ALL)

# The gtest/gtest_main targets carry header search path
# dependencies automatically when using CMake 2.8.11 or
# later. Otherwise we have to add them here ourselves.
if (CMAKE_VERSION VERSION_LESS 2.8.11)
  include_directories("${gtest_SOURCE_DIR}/include")
endif()

# Now simply link against gtest or gtest_main as needed. Eg
include_directories(${CMAKE_CURRENT_BINARY_DIR})
include_directories("${gtest_SOURCE_DIR}/include")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -lgtest")


#p2p
smi_target(test_p2p "${CMAKE_CURRENT_SOURCE_DIR}/p2p/p2p.json" "${CMAKE_CURRENT_SOURCE_DIR}/p2p/test_p2p.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/p2p/p2p_rank0.cl;${CMAKE_CURRENT_SOURCE_DIR}/p2p/p2p_rank1.cl" 8)
target_link_libraries(test_p2p_host gtest)
add_test(
   NAME p2p
   COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_p2p_host
   WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_p2p/"
 )


#broadcast
smi_target(test_broadcast "${CMAKE_CURRENT_SOURCE_DIR}/broadcast/broadcast.json" "${CMAKE_CURRENT_SOURCE_DIR}/broadcast/test_broadcast.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/broadcast/broadcast.cl" 8)
target_link_libraries(test_broadcast_host gtest)

add_test(
  NAME broadcast
  COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_broadcast_host
  WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_broadcast/"
)

#treecast
smi_target(test_treecast "${CMAKE_CURRENT_SOURCE_DIR}/treecast/treecast.json" "${CMAKE_CURRENT_SOURCE_DIR}/treecast/test_treecast.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/treecast/treecast.cl" 8)
target_link_libraries(test_treecast_host gtest)

add_test(
  NAME treecast
  COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_treecast_host
  WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_treecast/"
)


#barrier
smi_target(test_barrier "${CMAKE_CURRENT_SOURCE_DIR}/barrier/barrier.json" "${CMAKE_CURRENT_SOURCE_DIR}/barrier/test_barrier.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/barrier/barrier.cl" 8)
target_link_libraries(test_barrier_host gtest)

add_test(
  NAME barrier
  COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_barrier_host
  WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_barrier/"
)

#reduce
smi_target(test_reduce "${CMAKE_CURRENT_SOURCE_DIR}/reduce/reduce.json" "${CMAKE_CURRENT_SOURCE_DIR}/reduce/test_reduce.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/reduce/reduce.cl" 8)
target_link_libraries(test_reduce_host gtest)

add_test(
   NAME reduce
   COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_reduce_host
   WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_reduce/"
 )

#treereduce
smi_target(test_treereduce "${CMAKE_CURRENT_SOURCE_DIR}/treereduce/treereduce.json" "${CMAKE_CURRENT_SOURCE_DIR}/treereduce/test_treereduce.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/treereduce/treereduce.cl" 8)
target_link_libraries(test_treereduce_host gtest)

add_test(
   NAME treereduce
   COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_treereduce_host
   WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_treereduce/"
 )


smi_target(test_scatter "${CMAKE_CURRENT_SOURCE_DIR}/scatter/scatter.json" "${CMAKE_CURRENT_SOURCE_DIR}/scatter/test_scatter.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/scatter/scatter.cl" 8)
target_link_libraries(test_scatter_host gtest)

add_test(
   NAME scatter
   COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_scatter_host
   WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_scatter/"
 )

smi_target(test_gather "${CMAKE_CURRENT_SOURCE_DIR}/gather/gather.json" "${CMAKE_CURRENT_SOURCE_DIR}/gather/test_gather.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/gather/gather.cl" 8)
target_link_libraries(test_gather_host gtest)

add_test(
   NAME gather
   COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_gather_host
   WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_gather/"
 )


smi_target(test_mixed "${CMAKE_CURRENT_SOURCE_DIR}/mixed/mixed.json" "${CMAKE_CURRENT_SOURCE_DIR}/mixed/test_mixed.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/mixed/mixed.cl" 8)
target_link_libraries(test_mixed_host gtest)

add_test(
   NAME mixed
   COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_mixed_host
   WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_mixed/"
 )

smi_target(test_balanced_routing "${CMAKE_CURRENT_SOURCE_DIR}/balanced_routing/balanced_routing.json" "${CMAKE_CURRENT_SOURCE_DIR}/balanced_routing/test_balanced_routing.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/balanced_routing/balanced_routing.cl" 8 8 8 OFF)
target_link_libraries(test_balanced_routing_host gtest)

add_test(
   NAME balanced_routing
   COMMAND  env  CL_CONTEXT_EMULATOR_DEVICE_INTELFPGA=8 mpirun -np 8 test_balanced_routing
   WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test_balanced_routing/"
 )
