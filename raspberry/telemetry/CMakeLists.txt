cmake_minimum_required(VERSION 3.16)
project(pocketnet_telemetry LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Protobuf REQUIRED)
find_package(PkgConfig REQUIRED)
find_package(OpenSSL REQUIRED)
find_package(SQLite3 REQUIRED)
find_package(CURL REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(Threads REQUIRED)
pkg_check_modules(GRPC REQUIRED IMPORTED_TARGET grpc++)
find_program(GRPC_CPP_PLUGIN grpc_cpp_plugin)
if(NOT GRPC_CPP_PLUGIN)
    message(FATAL_ERROR "Install the gRPC C++ protoc plugin (protobuf-compiler-grpc)")
endif()

set(PROTO_DIR "${CMAKE_CURRENT_SOURCE_DIR}/proto")
set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_DIR}")
add_custom_command(
    OUTPUT "${GENERATED_DIR}/monitoring.pb.cc" "${GENERATED_DIR}/monitoring.pb.h"
           "${GENERATED_DIR}/monitoring.grpc.pb.cc" "${GENERATED_DIR}/monitoring.grpc.pb.h"
    COMMAND protobuf::protoc
            "--proto_path=${PROTO_DIR}" "--cpp_out=${GENERATED_DIR}"
            "--grpc_out=${GENERATED_DIR}" "--plugin=protoc-gen-grpc=${GRPC_CPP_PLUGIN}"
            "${PROTO_DIR}/monitoring.proto"
    DEPENDS "${PROTO_DIR}/monitoring.proto"
    VERBATIM
)
add_library(telemetry_proto STATIC
    "${GENERATED_DIR}/monitoring.pb.cc" "${GENERATED_DIR}/monitoring.grpc.pb.cc")
target_include_directories(telemetry_proto PUBLIC "${GENERATED_DIR}")
target_link_libraries(telemetry_proto PUBLIC protobuf::libprotobuf PkgConfig::GRPC)

add_library(telemetry_core STATIC src/collectors.cpp src/event_store.cpp src/runtime.cpp)
target_include_directories(telemetry_core PUBLIC src)
target_link_libraries(telemetry_core PUBLIC telemetry_proto
    PRIVATE OpenSSL::Crypto CURL::libcurl nlohmann_json::nlohmann_json Threads::Threads)

add_executable(piagent-telemetry src/main.cpp)
add_library(device_authorization STATIC src/device_authorization.cpp)
target_link_libraries(device_authorization PRIVATE OpenSSL::Crypto SQLite::SQLite3)
target_link_libraries(piagent-telemetry PRIVATE telemetry_core device_authorization Threads::Threads)
install(TARGETS piagent-telemetry RUNTIME DESTINATION bin)

include(CTest)
if(BUILD_TESTING)
    add_executable(collectors_test tests/collectors_test.cpp)
    target_link_libraries(collectors_test PRIVATE telemetry_core nlohmann_json::nlohmann_json Threads::Threads)
    add_test(NAME collectors COMMAND collectors_test)
    add_executable(event_store_test tests/event_store_test.cpp)
    target_link_libraries(event_store_test PRIVATE telemetry_core device_authorization OpenSSL::Crypto SQLite::SQLite3)
    add_test(NAME event_store COMMAND event_store_test)
    add_executable(telemetry_stream_test tests/stream_test.cpp)
    target_link_libraries(telemetry_stream_test PRIVATE telemetry_core OpenSSL::Crypto SQLite::SQLite3)
    add_test(NAME telemetry_stream COMMAND telemetry_stream_test $<TARGET_FILE:piagent-telemetry>)
    set_tests_properties(telemetry_stream PROPERTIES TIMEOUT 22)
endif()
