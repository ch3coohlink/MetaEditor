#ifdef _WIN32
#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <moonbit.h>

moonbit_string_t metaeditor_service_get_tmp_path() {
  WCHAR buffer[MAX_PATH + 1];
  DWORD len = GetTempPath2W(MAX_PATH, buffer);
  if (len == 0) {
    return NULL;
  }
  moonbit_string_t str = moonbit_make_string_raw(len);
  memcpy(str, buffer, len * sizeof(WCHAR));
  return str;
}

int32_t metaeditor_service_current_pid() {
  return (int32_t)GetCurrentProcessId();
}

static HANDLE metaeditor_service_state_file = INVALID_HANDLE_VALUE;

int32_t metaeditor_service_retain_state_file(moonbit_string_t path) {
  int32_t len = Moonbit_array_length(path);
  WCHAR *buffer = (WCHAR *)malloc((len + 1) * sizeof(WCHAR));
  if (buffer == NULL) {
    return 0;
  }
  memcpy(buffer, path, len * sizeof(WCHAR));
  buffer[len] = L'\0';
  HANDLE file = CreateFileW(
    buffer,
    GENERIC_READ,
    FILE_SHARE_READ | FILE_SHARE_WRITE,
    NULL,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    NULL
  );
  free(buffer);
  if (file == INVALID_HANDLE_VALUE) {
    return 0;
  }
  if (metaeditor_service_state_file != INVALID_HANDLE_VALUE) {
    CloseHandle(metaeditor_service_state_file);
  }
  metaeditor_service_state_file = file;
  return 1;
}

void metaeditor_service_release_state_file() {
  if (metaeditor_service_state_file != INVALID_HANDLE_VALUE) {
    CloseHandle(metaeditor_service_state_file);
    metaeditor_service_state_file = INVALID_HANDLE_VALUE;
  }
}

int32_t metaeditor_service_process_exists(int32_t pid) {
  HANDLE process = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  if (process == NULL) {
    return 0;
  }
  DWORD exit_code = 0;
  BOOL ok = GetExitCodeProcess(process, &exit_code);
  CloseHandle(process);
  if (!ok) {
    return 0;
  }
  return exit_code == STILL_ACTIVE ? 1 : 0;
}

int32_t metaeditor_service_terminate_process(int32_t pid) {
  HANDLE process = OpenProcess(PROCESS_TERMINATE | SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  if (process == NULL) {
    return 0;
  }
  BOOL ok = TerminateProcess(process, 0);
  if (ok) {
    WaitForSingleObject(process, 5000);
  }
  CloseHandle(process);
  return ok ? 1 : 0;
}

#else
#include <moonbit.h>
#include <stdint.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

moonbit_string_t metaeditor_service_get_tmp_path() {
  const char *path = getenv("TMPDIR");
  if (!path || path[0] == '\0') {
    path = "/tmp/";
  }
  size_t len = strlen(path);
  moonbit_string_t str = moonbit_make_string_raw(len);
  for (size_t i = 0; i < len; i++) {
    ((uint16_t *)str)[i] = (uint16_t)(unsigned char)path[i];
  }
  return str;
}

int32_t metaeditor_service_current_pid() {
  return (int32_t)getpid();
}

int32_t metaeditor_service_retain_state_file(moonbit_string_t path) {
  (void)path;
  return 1;
}

void metaeditor_service_release_state_file() {
}

int32_t metaeditor_service_process_exists(int32_t pid) {
  if (pid <= 0) {
    return 0;
  }
  if (kill((pid_t)pid, 0) == 0) {
    return 1;
  }
  return errno == EPERM ? 1 : 0;
}

int32_t metaeditor_service_terminate_process(int32_t pid) {
  if (pid <= 0) {
    return 0;
  }
  return kill((pid_t)pid, SIGTERM) == 0 ? 1 : 0;
}

#endif
