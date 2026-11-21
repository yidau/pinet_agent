cmake_minimum_required(VERSION 3.20)
project(piagent_queue LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)
enable_testing()
add_executable(queue_test queue_test.cpp)
target_link_libraries(queue_test PRIVATE Threads::Threads)
add_test(NAME producer_consumer_queue COMMAND queue_test)
set_tests_properties(producer_consumer_queue PROPERTIES TIMEOUT 20)
