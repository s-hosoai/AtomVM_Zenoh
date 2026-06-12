if (IDF_VERSION_MAJOR GREATER_EQUAL 5)
    set(OPTIONAL_WHOLE_ARCHIVE WHOLE_ARCHIVE)
else()
    set(OPTIONAL_WHOLE_ARCHIVE "")
endif()

idf_component_register(
    SRCS
        "m5unified_nif.cpp"
        "m5unified_reg.c"
    PRIV_REQUIRES
        "libatomvm"
        "avm_sys"
        "m5stack__M5Unified"
    ${OPTIONAL_WHOLE_ARCHIVE}
)

target_compile_features(${COMPONENT_LIB} INTERFACE cxx_std_17)
