cmake_minimum_required (VERSION 3.8)
project (flow D)
set(CMAKE_BUILD_TYPE Debug)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY bin)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ext)

enable_testing()

# build libflow-core
set(FLOW_CORE_SRC "src/core")
file(GLOB _FLOW_CORE_SRC RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} "${FLOW_CORE_SRC}/flow/*/*.d")
add_library(flow-core SHARED "${_FLOW_CORE_SRC}")
target_compile_options(flow-core PRIVATE "-H")
target_compile_options(flow-core PRIVATE "-op")
target_include_directories(flow-core PRIVATE "${FLOW_CORE_SRC}")
target_add_unittests(flow-core "${_FLOW_CORE_SRC}")

#target_add_unittests(flow-core "${FLOW_CORE_SRC}/flow/data/engine.d")

#add_unittests(${_FLOW_CORE_SRC})
#file(GLOB files RELATIVE "${FLOW_CORE_SRC}/flow/core/" "*.d")
#foreach(file IN LISTS files)
#  add_unittests(${file})
#endforeach()
#foreach(MODULE IN LISTS ${_FLOW_CORE_SRC})
#    add_unittests(${MODULE})
#endforeach()

# LIBRARIES
# build libnanomsg static
#set (NANOMSG_SRC "${CMAKE_CURRENT_SOURCE_DIR}/src/lib/nanomsg")
#file(GLOB _NANOMSG_SRC ${NANOMSG_SRC}/deimos/nanomsg/*.d)

#add_library(nanomsg ${_NANOMSG_SRC})
#target_compile_options(nanomsg PRIVATE "-H")
#target_compile_options(nanomsg PRIVATE "-op")
#target_include_directories(nanomsg PRIVATE "${NANOMSG_SRC}")

# EXTENSIONS
# build libflow-ipc-nanomsg
#set (FLOW_IPC_NANOMSG_SRC "${CMAKE_CURRENT_SOURCE_DIR}/src/ext/ipc-nanomsg")
#file(GLOB _FLOW_IPC_NANOMSG_SRC ${FLOW_IPC_NANOMSG_SRC}/flow/*/*.d)
#add_library(flow-ipc-nanomsg SHARED ${_FLOW_IPC_NANOMSG_SRC})

#add_dependencies(flow-ipc-nanomsg nanomsg)
#add_dependencies(flow-ipc-nanomsg flow-core)
#target_link_libraries(flow-ipc-nanomsg nanomsg)
#target_link_libraries(flow-ipc-nanomsg flow-core)
#target_include_directories(flow-ipc-nanomsg PRIVATE "${FLOW_IPC_NANOMSG_SRC}")
#target_include_directories(flow-ipc-nanomsg PRIVATE "${NANOMSG_SRC}")
#target_include_directories(flow-ipc-nanomsg PRIVATE "${FLOW_CORE_SRC}")

# build libflow-complex
#set (FLOW_COMPLEX_SRC "${CMAKE_CURRENT_SOURCE_DIR}/src/ext/complex")
#file(GLOB _FLOW_COMPLEX_SRC ${FLOW_COMPLEX_SRC}/flow/*/*.d)
#add_library(flow-complex SHARED ${_FLOW_COMPLEX_SRC})

#add_dependencies(flow-complex nanomsg)
#add_dependencies(flow-complex flow-core)
#target_link_libraries(flow-complex flow-core)
#target_include_directories(flow-complex PRIVATE "${FLOW_COMPLEX_SRC}")
#target_include_directories(flow-complex PRIVATE "${FLOW_CORE_SRC}")

# EXECUTABLES
# build flow-run
#set (FLOW_RUN_SRC "${CMAKE_CURRENT_SOURCE_DIR}/src/bin/run")
#file(GLOB _FLOW_RUN_SRC ${FLOW_RUN_SRC}/flow/*.d)
#add_executable(flow-run ${_FLOW_RUN_SRC})

#add_dependencies(flow-run flow-core)
#target_link_libraries(flow-run flow-core)
#target_include_directories(flow-run PRIVATE "${FLOW_RUN_SRC}")
#target_include_directories(flow-run PRIVATE "${FLOW_CORE_SRC}")

# build flow-complex-gen
#set (FLOW_COMPLEX_GEN_SRC "${CMAKE_CURRENT_SOURCE_DIR}/src/bin/complex-gen")
#file(GLOB _FLOW_COMPLEX_GEN_SRC ${FLOW_COMPLEX_GEN_SRC}/flow/*/*.d)
#add_executable(flow-complex-gen ${_FLOW_COMPLEX_GEN_SRC})

#add_dependencies(flow-complex-gen flow-core)
#target_link_libraries(flow-complex-gen flow-core)
#target_link_libraries(flow-complex-gen flow-complex)
#target_include_directories(flow-complex-gen PRIVATE "${FLOW_COMPLEX_GEN_SRC}")
#target_include_directories(flow-complex-gen PRIVATE "${FLOW_CORE_SRC}")
#target_include_directories(flow-complex-gen PRIVATE "${FLOW_COMPLEX_SRC}")
