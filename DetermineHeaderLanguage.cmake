# /DetermineHeaderLanguage.cmake
#
# CMake utility to determine the languages of a header file. This information
# can be used to determine which language mode certain tools should run in.
#
# See /LICENCE.md for Copyright information
if (NOT BIICODE)

    set (CMAKE_MODULE_PATH
         "${CMAKE_CURRENT_LIST_DIR}/bii/deps"
         "${CMAKE_MODULE_PATH}")

endif ()

include ("smspillaz/cmake-include-guard/IncludeGuard")
cmake_include_guard (SET_MODULE_PATH)

include (CMakeParseArguments)

if (POLICY CMP0054)

    cmake_policy (SET CMP0054 NEW)

endif ()

function (_psq_get_absolute_path_to_header_file_language ABSOLUTE_PATH_TO_HEADER
                                                         LANGUAGE)

    # ABSOLUTE_PATH is a GLOBAL property
    # called "_PSQ_DETERMINE_LANG_LANGUAGE_" + ABSOLUTE_PATH.
    # We can't address it immediately by that name though,
    # because CMake properties and variables can only be
    # addressed by certain characters, however, internally,
    # they are stored as std::map <std::string, std::string>,
    # so we can fool CMake into doing so.
    #
    # We first save our desired property string into a new
    # variable called MAP_KEY and then use set
    # ("${MAP_KEY}" ${LANGUAGE}). CMake will expand ${MAP_KEY}
    # and pass the string directly to the internal
    # implementation of "set", which sets the string
    # as the key value
    set (MAP_KEY "_PSQ_DETERMINE_LANG_LANGUAGE_${ABSOLUTE_PATH_TO_HEADER}")
    set (HEADER_FILE_LANGUAGE "${${MAP_KEY}}")

    # If it is just C, check our _PSQ_DETERMINE_LANG_HAS_CXX_TOKENS_ to see
    # if this is actually a mixed mode header.
    if ("${HEADER_FILE_LANGUAGE}" STREQUAL "C")

        set (MIXED_MODE_MAP_KEY
             "_PSQ_DETERMINE_LANG_HAS_CXX_TOKENS_${ABSOLUTE_PATH_TO_HEADER}")
        set (IS_MIXED_MODE "${${MIXED_MODE_MAP_KEY}}")

        if (IS_MIXED_MODE)

            list (APPEND HEADER_FILE_LANGUAGE "CXX")

        endif ()

    endif ()

    set (${LANGUAGE} ${HEADER_FILE_LANGUAGE} PARENT_SCOPE)

endfunction ()

# psq_source_type_from_source_file_extension:
#
# Returns the initial type of a source file from its extension. It doesn't
# properly analyze headers and source inclusions to determine the language
# of any headers.
#
# The type of the source will be set in the variable specified in
# RETURN_TYPE. Valid values are C_SOURCE, CXX_SOURCE, HEADER and UNKNOWN
#
# SOURCE: Source file to scan
# RETURN_TYPE: Variable to set the source type in
function (psq_source_type_from_source_file_extension SOURCE RETURN_TYPE)

    # HEADER_FILE_ONLY overrides everything else
    get_property (HEADER_FILE_ONLY
                  SOURCE "${SOURCE}"
                  PROPERTY HEADER_FILE_ONLY)

    if (HEADER_FILE_ONLY)

        set (${RETURN_TYPE} "HEADER" PARENT_SCOPE)
        return ()

    endif ()

    # Try and detect the language based on the file's extension
    get_filename_component (EXTENSION "${SOURCE}" EXT)
    if (EXTENSION)

        string (SUBSTRING ${EXTENSION} 1 -1 EXTENSION)

        list (FIND CMAKE_C_SOURCE_FILE_EXTENSIONS ${EXTENSION} C_INDEX)

        if (NOT C_INDEX EQUAL -1)

            set (${RETURN_TYPE} "C_SOURCE" PARENT_SCOPE)
            return ()

        endif ()

        list (FIND CMAKE_CXX_SOURCE_FILE_EXTENSIONS ${EXTENSION} CXX_INDEX)

        if (NOT CXX_INDEX EQUAL -1)

            set (${RETURN_TYPE} "CXX_SOURCE" PARENT_SCOPE)
            return ()

        endif ()

        # CMake doesn't provide a list of header file extensions. Here are
        # some common ones.
        #
        # Notably absent are files without an extension. It appears that these
        # are not used outside the standard library and Qt. There's very
        # little chance that we will be scanning them.
        #
        # If they do need to be scanned, consider having the extensionless
        # header include a header with an extension and scanning that instead.
        set (HEADER_EXTENSIONS h hh hpp hxx H HPP h++)

        list (FIND HEADER_EXTENSIONS ${EXTENSION} HEADER_INDEX)

        if (NOT HEADER_INDEX EQUAL -1)

            set (${RETURN_TYPE} "HEADER" PARENT_SCOPE)
            return ()

        endif ()

    endif ()

    # If we got to this point, then we don't know, set UNKNOWN
    set (${RETURN_TYPE} "UNKNOWN" PARENT_SCOPE)

endfunction ()

function (_psq_language_from_source SOURCE
                                    RETURN_LANGUAGE
                                    SOURCE_WAS_HEADER_RETURN)

    cmake_parse_arguments (LANG_FROM_SOURCE
                           ""
                           "FORCE_LANGUAGE"
                           ""
                           ${ARGN})

    set (${SOURCE_WAS_HEADER_RETURN} FALSE PARENT_SCOPE)
    set (_RETURN_LANGUAGE "")

    psq_source_type_from_source_file_extension ("${SOURCE}" SOURCE_TYPE)

    if ("${SOURCE_TYPE}" STREQUAL "C_SOURCE")

        set (_RETURN_LANGUAGE "C")

    elseif ("${SOURCE_TYPE}" STREQUAL "CXX_SOURCE")

        set (_RETURN_LANGUAGE "CXX")

    elseif ("${SOURCE_TYPE}" STREQUAL "HEADER")

        set (${SOURCE_WAS_HEADER_RETURN} TRUE PARENT_SCOPE)
        # Couldn't find source language from either extension or property.
        # We might be scanning a header so check the header maps for a language
        set (LANGUAGE "")
        _psq_get_absolute_path_to_header_file_language ("${SOURCE}" LANGUAGE)
        set (_RETURN_LANGUAGE ${LANGUAGE})

    elseif ("${SOURCE_TYPE}" STREQUAL "UNKNOWN")

        message (FATAL_ERROR
                 "The file ${SOURCE} is not a C or C++ source, and is not a "
                 "header. It should not be passed to "
                 "psq_scan_source_for_headers")

    endif ()

    # Override language based on option here after we've scanned everything
    # and worked out if this was a header or not
    if (LANG_FROM_SOURCE_FORCE_LANGUAGE)

        set (_RETURN_LANGUAGE ${LANG_FROM_SOURCE_FORCE_LANGUAGE})

    else ()

        get_property (LANGUAGE SOURCE "${SOURCE}" PROPERTY SET_LANGUAGE)

        # User overrode the LANGUAGE property, use that.
        if (DEFINED SET_LANGUAGE)

            set (_RETURN_LANGUAGE ${SET_LANGUAGE})

        endif ()

    endif ()

    set (${RETURN_LANGUAGE} ${_RETURN_LANGUAGE} PARENT_SCOPE)

endfunction ()

function (_psq_process_include_statement_path INCLUDE_PATH
                                              UPDATE_HEADERS_RETURN)
    set (HEADERS_TO_UPDATE_LIST)
    set (PROCESS_MULTIVAR_ARGS INCLUDES)

    cmake_parse_arguments (PROCESS
                           ""
                           ""
                           "${PROCESS_MULTIVAR_ARGS}"
                           ${ARGN})

    foreach (INCLUDE_DIRECTORY ${PROCESS_INCLUDES})

        set (RELATIVE_PATH "${INCLUDE_DIRECTORY}/${INCLUDE_PATH}")
        get_filename_component (ABSOLUTE_PATH "${RELATIVE_PATH}" ABSOLUTE)

        get_property (HEADER_IS_GENERATED SOURCE "${ABSOLUTE_PATH}"
                      PROPERTY GENERATED)

        if (EXISTS "${ABSOLUTE_PATH}" OR HEADER_IS_GENERATED)

            # First see if a language has already been set for this header
            # file. If so, and it is "C", then we can't change it any
            # further at this point.
            set (HEADER_LANGUAGE "")
            _psq_get_absolute_path_to_header_file_language ("${ABSOLUTE_PATH}"
                                                            HEADER_LANGUAGE)

            list (FIND HEADER_LANGUAGE "C" C_INDEX)

            if (DEFINED HEADER_LANGUAGE AND
                C_INDEX EQUAL -1)

                list (APPEND HEADERS_TO_UPDATE_LIST "${ABSOLUTE_PATH}")

            elseif (NOT DEFINED HEADER_LANGUAGE AND C_INDEX EQUAL -1)

                list (APPEND HEADERS_TO_UPDATE_LIST "${ABSOLUTE_PATH}")

            endif ()

        endif ()

    endforeach ()

    set (${UPDATE_HEADERS_RETURN} ${HEADERS_TO_UPDATE_LIST} PARENT_SCOPE)

endfunction ()

# psq_scan_source_for_headers
#
# Opens the source file SOURCE at its absolute path and scans it for
# #include statements if we have not done so already. The content of the
# include statement is pasted together with each provided INCLUDE
# and checked to see if it forms the path to an existing or generated
# source. If it does, then the following rules apply to determine
# the language of the header file:
#
# - If the source including the header is a CXX source (including a CXX
#   header, and no other language has been set for this header, then
#   the language of the header is set to CXX
# - If any source including the header is a C source (including a C header)
#   then the language of the header is forced to "C", with one caveat:
#   - The header file will be opened and scanned for any tokens which match
#     any provided tokens in CPP_IDENTIFIERS or __cplusplus. If it does, then
#     the header language will be set to C;CXX
#
# SOURCE: The source file to be scanned
# [Optional] INCLUDES: Any include directories to search for header files
# [Optional] CPP_IDENTIFIERS: Any identifiers which might indicate that this
#                             source can be compiled with both C and CXX.
function (psq_scan_source_for_headers)

    set (SCAN_SINGLEVAR_ARGUMENTS SOURCE)
    set (SCAN_MULTIVAR_ARGUMENTS INCLUDES CPP_IDENTIFIERS)

    cmake_parse_arguments (SCAN
                           ""
                           "${SCAN_SINGLEVAR_ARGUMENTS}"
                           "${SCAN_MULTIVAR_ARGUMENTS}"
                           ${ARGN})

    if (NOT DEFINED SCAN_SOURCE)

        message (FATAL_ERROR "SOURCE ${SCAN_SOURCE} must be "
                             "set to use this function")

    endif ()

    # Source doesn't exist. This is fine, we might be recursively scanning
    # a header path which is generated. If it is generated, gracefully bail
    # out, otherwise exit with a FATAL_ERROR as this is really an assertion
    if (NOT EXISTS "${SCAN_SOURCE}")

        get_property (SOURCE_IS_GENERATED SOURCE "${SCAN_SOURCE}"
                      PROPERTY GENERATED)

        if (SOURCE_IS_GENERATED)

            return ()

        else ()

            message (FATAL_ERROR "_scan_source_file_for_headers called with "
                                 "a source file that does not exist or was "
                                 "not generated as part of a build rule")

        endif ()

    endif ()

    # We've already scanned this source file in this pass, bail out
    get_property (ALREADY_SCANNED GLOBAL
                  PROPERTY _PSQ_ALREADY_SCANNED_SOURCES)
    list (FIND ALREADY_SCANNED "${SCAN_SOURCE}" SOURCE_INDEX)

    if (NOT SOURCE_INDEX EQUAL -1)

        return ()

    endif ()

    set_property (GLOBAL APPEND PROPERTY _PSQ_ALREADY_SCANNED_SOURCES
                  "${SCAN_SOURCE}")

    set (HEADER_PATHS_MAP_KEY "_PSQ_DETERMINE_LANG_HEADERS_${SCAN_SOURCE}")
    set (HAS_CXX_TOKENS_MAP_KEY
         "_PSQ_DETERMINE_LANG_HAS_CXX_TOKENS_${SCAN_SOURCE}")
    set (SCANNED_CXX_TOKENS_MAP_KEY
         "_PSQ_DETERMINE_LANG_SCANNED_CXX_TOKENS_${SCAN_SOURCE}")
    set (FILE_TIMESTAMP_MAP_KEY
         "_PSQ_DETERMINE_LANG_SCAN_TIMESTAMP_${SCAN_SOURCE}")

    # Check the source file's timestamp and then check it against what we have
    # in the cache. If it is different, or CPP_IDENTIFIERS are different, then
    # we need to re-scan this file
    file (TIMESTAMP "${SCAN_SOURCE}" FILE_TIMESTAMP)

    if (NOT "${FILE_TIMESTAMP}" STREQUAL "${${FILE_TIMESTAMP_MAP_KEY}}" OR
        NOT "${CPP_IDENTIFIERS}" STREQUAL "${${SCANNED_CXX_TOKENS_MAP_KEY}}")

        set ("${FILE_TIMESTAMP_MAP_KEY}"
             CACHE INTERNAL "" FORCE)

        # Open the source file and read its contents
        file (READ "${SCAN_SOURCE}" SOURCE_CONTENTS)

        # Split the read contents into lines, using ; as the delimiter
        string (REGEX REPLACE ";" "\\\\;" SOURCE_CONTENTS "${SOURCE_CONTENTS}")
        string (REGEX REPLACE "\n" ";" SOURCE_CONTENTS "${SOURCE_CONTENTS}")

        _psq_language_from_source ("${SCAN_SOURCE}" LANGUAGE WAS_HEADER)

        # If we are scanning a header file right now, the we need to check now
        # while reading it for other headers for CXX tokens too. If there are
        # CXX tokens, we'll keep it in our special
        # _PSQ_DETERMINE_LANG_HAS_CXX_TOKENS_
        set (SCAN_FOR_CXX_IDENTIFIERS "${WAS_HEADER}")

        foreach (LINE ${SOURCE_CONTENTS})

            # This is an #include statement, check what is within it
            if (LINE MATCHES "^.*\#include.*[<\"].*[>\"]")

                # Start with ${LINE}
                set (HEADER ${LINE})

                # Trim out the beginning and end of the include statement
                # Because CMake doesn't support non-greedy expressions (eg "?")
                # we need to match based on indices and not using REGEX REPLACE
                # so we need to use REGEX MATCH to get the first match and then
                # FIND to get the index.
                string (REGEX MATCH "[<\"]" PATH_START "${HEADER}")
                string (FIND "${HEADER}" "${PATH_START}" PATH_START_INDEX)
                math (EXPR PATH_START_INDEX "${PATH_START_INDEX} + 1")
                string (SUBSTRING "${HEADER}" ${PATH_START_INDEX} -1 HEADER)

                string (REGEX MATCH "[>\"]" PATH_END "${HEADER}")
                string (FIND "${HEADER}" "${PATH_END}" PATH_END_INDEX)
                string (SUBSTRING "${HEADER}" 0 ${PATH_END_INDEX} HEADER)

                string (STRIP "${HEADER}" HEADER)

                # Check if this include statement has quotes. If it does, then
                # we should include the current source directory in the include
                # directory scan.
                string (FIND "${LINE}" "\"" QUOTE_INDEX)

                if (NOT QUOTE_INDEX EQUAL -1)

                    list (APPEND SCAN_INCLUDES "${CMAKE_CURRENT_SOURCE_DIR}")

                endif ()

                _psq_process_include_statement_path ("${HEADER}" UPDATE_HEADERS
                                                     INCLUDES ${SCAN_INCLUDES})

                # Every correct combination of include-directory to header
                foreach (HEADER ${UPDATE_HEADERS})

                    set (LANGUAGE_MAP_KEY
                         "_PSQ_DETERMINE_LANG_LANGUAGE_${HEADER}")
                    set ("${LANGUAGE_MAP_KEY}" "${LANGUAGE}"
                         CACHE INTERNAL "" FORCE)

                    list (FIND "${HEADER_PATHS_MAP_KEY}" "${HEADER}"
                          PATH_TO_SCAN_INDEX)

                    # Append the header to the list of headers for this
                    # source file.
                    if (PATH_TO_SCAN_INDEX EQUAL -1)

                        list (APPEND "${HEADER_PATHS_MAP_KEY}" "${HEADER}")
                        set ("${HEADER_PATHS_MAP_KEY}"
                             "${${HEADER_PATHS_MAP_KEY}}"
                             CACHE INTERNAL "" FORCE)

                    endif ()

                    # Append the header to the list of candidate headers
                    # globally
                    get_property (CANDIDATE_HEADERS GLOBAL
                                  PROPERTY _PSQ_CANDIDATE_HEADERS)
                    list (FIND CANDIDATE_HEADERS "${HEADER}"
                          CANDIDATE_HEADER_INDEX)

                    if (CANDIDATE_HEADER_INDEX EQUAL -1)

                        set_property (GLOBAL APPEND PROPERTY
                                      _PSQ_CANDIDATE_HEADERS
                                      "${HEADER}")

                    endif ()

                endforeach ()

            endif ()

            if (SCAN_FOR_CXX_IDENTIFIERS)

                list (APPEND SCAN_CPP_IDENTIFIERS
                      "__cplusplus")
                list (REMOVE_DUPLICATES SCAN_CPP_IDENTIFIERS)

                foreach (IDENTIFIER ${SCAN_CPP_IDENTIFIERS})

                    if (LINE MATCHES "^.*${IDENTIFIER}")

                        set ("${HAS_CXX_TOKENS_MAP_KEY}" TRUE
                             CACHE INTERNAL "" FORCE)
                        set ("${SCANNED_CXX_TOKENS_MAP_KEY}"
                             ${SCAN_CPP_IDENTIFIERS}
                             CACHE INTERNAL "" FORCE)
                        set (SCAN_FOR_CXX_IDENTIFIERS FALSE)

                    endif ()

                endforeach ()

            endif ()

        endforeach ()

    endif (NOT "${FILE_TIMESTAMP}" STREQUAL "${${FILE_TIMESTAMP_MAP_KEY}}" OR
           NOT "${CPP_IDENTIFIERS}" STREQUAL "${${SCANNED_CXX_TOKENS_MAP_KEY}}")

    foreach (HEADER ${${HEADER_PATHS_MAP_KEY}})

        # Recursively scan for header more header files
        # in this one
        psq_scan_source_for_headers (SOURCE "${HEADER}"
                                            INCLUDES
                                            ${SCAN_INCLUDES}
                                            CPP_IDENTIFIERS
                                            ${SCAN_CPP_IDENTIFIERS})

    endforeach ()

endfunction ()

# psq_determine_language_for_source
#
# Takes any source, including a header file and writes the determined
# language into LANGUAGE_RETURN. If the source is a header file
# SOURCE_WAS_HEADER_RETURN will be set to true as well.
#
# This function only works for header files if those header files
# were included by sources previously scanned by
# psq_scan_source_for_headers. They must be scanned before
# this function is called, otherwise this function will be unable
# to determine the language of the source file and report an error.
#
# SOURCE: The source whose language is to be determined
# LANGUAGE_RETURN: A variable where the language can be written into
# SOURCE_WAS_HEADER_RETURN: A variable where a boolean variable, indicating
#                           whether this was a header or a source that was
#                           checked.
# [Optional] FORCE_LANGUAGE: Performs scanning, but forces language to be one
#                            of C or CXX.
function (psq_determine_language_for_source SOURCE
                                            LANGUAGE_RETURN
                                            SOURCE_WAS_HEADER_RETURN)

    set (DETERMINE_LANG_MULTIVAR_ARGS INCLUDES)
    cmake_parse_arguments (DETERMINE_LANG
                           ""
                           "FORCE_LANGUAGE"
                           "${DETERMINE_LANG_MULTIVAR_ARGS}"
                           ${ARGN})

    if (DETERMINE_LANG_FORCE_LANGUAGE)

        set (LANG_FROM_SOURCE_FORCE_LANGUAGE_OPT
             FORCE_LANGUAGE ${DETERMINE_LANG_FORCE_LANGUAGE})

    endif ()

    _psq_language_from_source ("${SOURCE}" LANGUAGE WAS_HEADER
                               ${LANG_FROM_SOURCE_FORCE_LANGUAGE_OPT})
    set (${SOURCE_WAS_HEADER_RETURN} "${WAS_HEADER}" PARENT_SCOPE)

    # If it wasn't a header or language was forced, then the answer
    # we got back was the authority. There's no need to check for
    # mixed mode headers or the like.
    if (NOT WAS_HEADER OR DETERMINE_LANG_FORCE_LANGUAGE)

        set (${LANGUAGE_RETURN} ${LANGUAGE} PARENT_SCOPE)
        return ()

    else ()

        set (${SOURCE_WAS_HEADER_RETURN} TRUE PARENT_SCOPE)

        # This is a header file - we need to look up in the list
        # of header files to determine what language this header
        # file is. That will generally be "C" if it was
        # included by any "C" source files and "CXX" if it was included
        # by any other (CXX) sources.
        #
        # There is also an error case - If we are unable to determine
        # the language of the header file initially, then it was never
        # added to the list of known headers. We'll error out with a message
        # suggesting that it must be included at least once somewhere, or
        # a FORCE_LANGUAGE option should be passed
        get_filename_component (ABSOLUTE_PATH "${SOURCE}" ABSOLUTE)
        _psq_get_absolute_path_to_header_file_language ("${ABSOLUTE_PATH}"
                                                        HEADER_LANGUAGE)

        # Error case
        if (NOT DEFINED HEADER_LANGUAGE)

            set (ERROR_MESSAGE "Couldn't find language for the header file"
                               " ${ABSOLUTE_PATH}. Make sure to include "
                               " this header file in at least one source "
                               " file and add that source file to a "
                               " target and scan it using "
                               " psq_scan_source_for_headers or specify"
                               " the FORCE_LANGUAGE option to the call to"
                               " psq_determine_language_for_source where"
                               " the header will be included in the arguments.")

            set (ERROR_MESSAGE "${ERROR_MESSAGE}\n The following sources have "
                               "been scanned for includes:\n")

            get_property (ALREADY_SCANNED GLOBAL PROPERTY
                          _PSQ_ALREADY_SCANNED_SOURCES)

            foreach (SOURCE ${ALREADY_SCANNED})

                set (ERROR_MESSAGE "${ERROR_MESSAGE} - ${SOURCE}\n")

            endforeach ()

            set (ERROR_MESSAGE "${ERROR_MESSAGE}\n The following headers are "
                               "marked as potential includes:\n")

            message (SEND_ERROR ${ERROR_MESSAGE})

            return ()

        endif ()

        set (${LANGUAGE_RETURN} ${HEADER_LANGUAGE} PARENT_SCOPE)
        return ()

    endif ()

    message (FATAL_ERROR "This section should not be reached")

endfunction ()
