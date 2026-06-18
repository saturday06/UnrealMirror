#pragma once

#include <stddef.h>

extern "C" int unreal_mirror_ipc_send_command(const char *command,
                                              const char *path,
                                              unsigned int timeout_ms,
                                              char *response,
                                              size_t response_len);
