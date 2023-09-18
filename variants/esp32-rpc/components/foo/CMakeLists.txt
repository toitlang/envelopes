file(GLOB C_FILES "*.c")

idf_component_register(
   REQUIRES toit
   SRCS ${C_FILES}
   WHOLE_ARCHIVE
)
