#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
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

int32_t metaeditor_service_port_ready(int32_t port) {
  if (port <= 0 || !metaeditor_service_init_winsock()) {
    return 0;
  }
  SOCKET sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (sock == INVALID_SOCKET) {
    return 0;
  }
  u_long nonblocking = 1;
  ioctlsocket(sock, FIONBIO, &nonblocking);
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((u_short)port);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  int rc = connect(sock, (SOCKADDR *)&addr, sizeof(addr));
  if (rc == SOCKET_ERROR) {
    int err = WSAGetLastError();
    if (err != WSAEWOULDBLOCK && err != WSAEINPROGRESS && err != WSAEALREADY) {
      closesocket(sock);
      return 0;
    }
    fd_set write_set;
    FD_ZERO(&write_set);
    FD_SET(sock, &write_set);
    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 0;
    rc = select(0, NULL, &write_set, NULL, &timeout);
    if (rc <= 0) {
      closesocket(sock);
      return 0;
    }
    int so_error = 0;
    int so_len = sizeof(so_error);
    if (
      getsockopt(sock, SOL_SOCKET, SO_ERROR, (char *)&so_error, &so_len) == SOCKET_ERROR ||
      so_error != 0
    ) {
      closesocket(sock);
      return 0;
    }
  }
  closesocket(sock);
  return 1;
}

static HANDLE metaeditor_service_state_file = INVALID_HANDLE_VALUE;
static int32_t metaeditor_service_test_last_error = 0;
static CRITICAL_SECTION metaeditor_service_trace_lock;
static int metaeditor_service_trace_lock_ready = 0;
static int metaeditor_service_wsa_ready = 0;

static WCHAR *metaeditor_service_copy_wstring(moonbit_string_t text) {
  int32_t len = Moonbit_array_length(text);
  WCHAR *buffer = (WCHAR *)malloc((len + 1) * sizeof(WCHAR));
  if (buffer == NULL) {
    return NULL;
  }
  memcpy(buffer, text, len * sizeof(WCHAR));
  buffer[len] = L'\0';
  return buffer;
}

static int metaeditor_service_append_wstring(WCHAR *dest, size_t cap, const WCHAR *src) {
  size_t len = wcslen(dest);
  size_t src_len = wcslen(src);
  if (len + src_len + 1 > cap) {
    return 0;
  }
  memcpy(dest + len, src, (src_len + 1) * sizeof(WCHAR));
  return 1;
}

static void metaeditor_service_init_trace_lock() {
  if (metaeditor_service_trace_lock_ready) {
    return;
  }
  InitializeCriticalSection(&metaeditor_service_trace_lock);
  metaeditor_service_trace_lock_ready = 1;
}

static int metaeditor_service_init_winsock() {
  if (metaeditor_service_wsa_ready) {
    return 1;
  }
  WSADATA data;
  if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
    return 0;
  }
  metaeditor_service_wsa_ready = 1;
  return 1;
}

void metaeditor_service_runtime_trace(moonbit_string_t message) {
  WCHAR temp_dir[MAX_PATH + 1];
  DWORD temp_len = GetTempPath2W(MAX_PATH, temp_dir);
  if (temp_len == 0 || temp_len > MAX_PATH) {
    return;
  }
  WCHAR path[MAX_PATH + 64];
  path[0] = L'\0';
  if (!metaeditor_service_append_wstring(path, MAX_PATH + 64, temp_dir)) {
    return;
  }
  if (!metaeditor_service_append_wstring(path, MAX_PATH + 64, L"metaeditor-runtime-trace.log")) {
    return;
  }

  int32_t len = Moonbit_array_length(message);
  metaeditor_service_init_trace_lock();
  EnterCriticalSection(&metaeditor_service_trace_lock);
  HANDLE file = CreateFileW(
    path,
    FILE_APPEND_DATA,
    FILE_SHARE_READ | FILE_SHARE_WRITE,
    NULL,
    OPEN_ALWAYS,
    FILE_ATTRIBUTE_NORMAL,
    NULL
  );
  if (file != INVALID_HANDLE_VALUE) {
    DWORD written = 0;
    WriteFile(file, message, (DWORD)(len * sizeof(WCHAR)), &written, NULL);
    static const WCHAR newline[2] = { L'\r', L'\n' };
    WriteFile(file, newline, sizeof(newline), &written, NULL);
    CloseHandle(file);
  }
  LeaveCriticalSection(&metaeditor_service_trace_lock);
}

static WCHAR *metaeditor_service_full_path(const WCHAR *path) {
  DWORD len = GetFullPathNameW(path, 0, NULL, NULL);
  if (len == 0) {
    return NULL;
  }
  WCHAR *full = (WCHAR *)malloc((len + 1) * sizeof(WCHAR));
  if (full == NULL) {
    return NULL;
  }
  if (GetFullPathNameW(path, len + 1, full, NULL) == 0) {
    free(full);
    return NULL;
  }
  return full;
}

static WCHAR *metaeditor_service_current_dir() {
  DWORD len = GetCurrentDirectoryW(0, NULL);
  if (len == 0) {
    return NULL;
  }
  WCHAR *dir = (WCHAR *)malloc((len + 1) * sizeof(WCHAR));
  if (dir == NULL) {
    return NULL;
  }
  if (GetCurrentDirectoryW(len + 1, dir) == 0) {
    free(dir);
    return NULL;
  }
  return dir;
}

static HANDLE metaeditor_service_open_null(DWORD access) {
  SECURITY_ATTRIBUTES attrs;
  ZeroMemory(&attrs, sizeof(attrs));
  attrs.nLength = sizeof(attrs);
  attrs.bInheritHandle = TRUE;
  return CreateFileW(
    L"NUL",
    access,
    FILE_SHARE_READ | FILE_SHARE_WRITE,
    &attrs,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    NULL
  );
}

int32_t metaeditor_service_spawn_background(
  moonbit_string_t exe,
  moonbit_string_t state_dir,
  int32_t port
) {
  WCHAR *exe_buf = metaeditor_service_copy_wstring(exe);
  WCHAR *state_dir_buf = metaeditor_service_copy_wstring(state_dir);
  WCHAR *exe_full = NULL;
  WCHAR *cwd_full = NULL;
  WCHAR *cmd = NULL;
  HANDLE stdin_handle = INVALID_HANDLE_VALUE;
  HANDLE stdout_handle = INVALID_HANDLE_VALUE;
  HANDLE stderr_handle = INVALID_HANDLE_VALUE;
  STARTUPINFOEXW startup_info;
  PROCESS_INFORMATION process_info;
  SIZE_T attr_size = 0;
  HANDLE inherit_handles[3];
  BOOL ok = FALSE;

  if (exe_buf == NULL || state_dir_buf == NULL) {
    free(exe_buf);
    free(state_dir_buf);
    return 0;
  }

  exe_full = metaeditor_service_full_path(exe_buf);
  cwd_full = metaeditor_service_current_dir();
  if (exe_full == NULL || cwd_full == NULL) {
    goto cleanup;
  }

  WCHAR port_buf[32];
  if (_itow_s((int)port, port_buf, 32, 10) != 0) {
    goto cleanup;
  }

  size_t cmd_len = wcslen(exe_full) + wcslen(state_dir_buf) + wcslen(port_buf) + 64;
  cmd = (WCHAR *)malloc((cmd_len + 1) * sizeof(WCHAR));
  if (cmd == NULL) {
    goto cleanup;
  }
  cmd[0] = L'\0';
  if (
    !metaeditor_service_append_wstring(cmd, cmd_len + 1, L"\"") ||
    !metaeditor_service_append_wstring(cmd, cmd_len + 1, exe_full) ||
    !metaeditor_service_append_wstring(cmd, cmd_len + 1, L"\" --internal_boot_as_service --state-dir \"") ||
    !metaeditor_service_append_wstring(cmd, cmd_len + 1, state_dir_buf) ||
    !metaeditor_service_append_wstring(cmd, cmd_len + 1, L"\" --port ") ||
    !metaeditor_service_append_wstring(cmd, cmd_len + 1, port_buf)
  ) {
    goto cleanup;
  }

  stdin_handle = metaeditor_service_open_null(GENERIC_READ);
  stdout_handle = metaeditor_service_open_null(GENERIC_WRITE);
  stderr_handle = metaeditor_service_open_null(GENERIC_WRITE);
  if (
    stdin_handle == INVALID_HANDLE_VALUE ||
    stdout_handle == INVALID_HANDLE_VALUE ||
    stderr_handle == INVALID_HANDLE_VALUE
  ) {
    goto cleanup;
  }

  ZeroMemory(&startup_info, sizeof(startup_info));
  ZeroMemory(&process_info, sizeof(process_info));
  startup_info.StartupInfo.cb = sizeof(startup_info);
  startup_info.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup_info.StartupInfo.hStdInput = stdin_handle;
  startup_info.StartupInfo.hStdOutput = stdout_handle;
  startup_info.StartupInfo.hStdError = stderr_handle;

  InitializeProcThreadAttributeList(NULL, 1, 0, &attr_size);
  startup_info.lpAttributeList =
    (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(attr_size);
  if (startup_info.lpAttributeList == NULL) {
    goto cleanup;
  }
  if (!InitializeProcThreadAttributeList(startup_info.lpAttributeList, 1, 0, &attr_size)) {
    goto cleanup;
  }

  inherit_handles[0] = stdin_handle;
  inherit_handles[1] = stdout_handle;
  inherit_handles[2] = stderr_handle;
  if (
    !UpdateProcThreadAttribute(
      startup_info.lpAttributeList,
      0,
      PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
      inherit_handles,
      sizeof(inherit_handles),
      NULL,
      NULL
    )
  ) {
    goto cleanup;
  }

  ok = CreateProcessW(
    exe_full,
    cmd,
    NULL,
    NULL,
    TRUE,
    EXTENDED_STARTUPINFO_PRESENT |
      CREATE_NO_WINDOW |
      CREATE_NEW_PROCESS_GROUP |
      CREATE_UNICODE_ENVIRONMENT,
    NULL,
    cwd_full,
    &startup_info.StartupInfo,
    &process_info
  );
  if (!ok) {
    goto cleanup;
  }

cleanup:
  if (process_info.hThread != NULL) {
    CloseHandle(process_info.hThread);
  }
  if (process_info.hProcess != NULL) {
    CloseHandle(process_info.hProcess);
  }
  if (startup_info.lpAttributeList != NULL) {
    DeleteProcThreadAttributeList(startup_info.lpAttributeList);
    free(startup_info.lpAttributeList);
  }
  if (stdin_handle != INVALID_HANDLE_VALUE) {
    CloseHandle(stdin_handle);
  }
  if (stdout_handle != INVALID_HANDLE_VALUE) {
    CloseHandle(stdout_handle);
  }
  if (stderr_handle != INVALID_HANDLE_VALUE) {
    CloseHandle(stderr_handle);
  }
  free(cmd);
  free(cwd_full);
  free(exe_full);
  free(state_dir_buf);
  free(exe_buf);
  return ok ? 1 : 0;
}

struct metaeditor_service_test_process {
  HANDLE process;
};

static HANDLE metaeditor_service_open_inheritable_file(const WCHAR *path) {
  SECURITY_ATTRIBUTES attrs;
  ZeroMemory(&attrs, sizeof(attrs));
  attrs.nLength = sizeof(attrs);
  attrs.bInheritHandle = TRUE;
  return CreateFileW(
    path,
    GENERIC_WRITE,
    FILE_SHARE_READ | FILE_SHARE_WRITE,
    &attrs,
    CREATE_ALWAYS,
    FILE_ATTRIBUTE_NORMAL,
    NULL
  );
}

static HANDLE metaeditor_service_open_inheritable_null() {
  SECURITY_ATTRIBUTES attrs;
  ZeroMemory(&attrs, sizeof(attrs));
  attrs.nLength = sizeof(attrs);
  attrs.bInheritHandle = TRUE;
  return CreateFileW(
    L"NUL",
    GENERIC_READ,
    FILE_SHARE_READ | FILE_SHARE_WRITE,
    &attrs,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    NULL
  );
}

uint64_t metaeditor_service_test_spawn(
  moonbit_string_t exe,
  moonbit_string_t command_line,
  moonbit_string_t cwd,
  moonbit_string_t stdout_path,
  moonbit_string_t stderr_path
) {
  metaeditor_service_test_last_error = 0;
  WCHAR *exe_buf = metaeditor_service_copy_wstring(exe);
  WCHAR *cmd_buf = metaeditor_service_copy_wstring(command_line);
  WCHAR *cwd_buf = metaeditor_service_copy_wstring(cwd);
  WCHAR *stdout_buf = metaeditor_service_copy_wstring(stdout_path);
  WCHAR *stderr_buf = metaeditor_service_copy_wstring(stderr_path);
  if (
    exe_buf == NULL ||
    cmd_buf == NULL ||
    cwd_buf == NULL ||
    stdout_buf == NULL ||
    stderr_buf == NULL
  ) {
    metaeditor_service_test_last_error = (int32_t)ERROR_OUTOFMEMORY;
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    free(stdout_buf);
    free(stderr_buf);
    return 0;
  }

  DWORD exe_full_len = GetFullPathNameW(exe_buf, 0, NULL, NULL);
  if (exe_full_len == 0) {
    metaeditor_service_test_last_error = (int32_t)GetLastError();
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    free(stdout_buf);
    free(stderr_buf);
    return 0;
  }
  WCHAR *exe_full = (WCHAR *)malloc((exe_full_len + 1) * sizeof(WCHAR));
  if (exe_full == NULL) {
    metaeditor_service_test_last_error = (int32_t)ERROR_OUTOFMEMORY;
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    free(stdout_buf);
    free(stderr_buf);
    return 0;
  }
  if (GetFullPathNameW(exe_buf, exe_full_len + 1, exe_full, NULL) == 0) {
    metaeditor_service_test_last_error = (int32_t)GetLastError();
    free(exe_full);
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    free(stdout_buf);
    free(stderr_buf);
    return 0;
  }

  size_t full_cmd_len = wcslen(exe_full) + wcslen(cmd_buf) + 4;
  WCHAR *full_cmd = (WCHAR *)malloc((full_cmd_len + 1) * sizeof(WCHAR));
  if (full_cmd == NULL) {
    metaeditor_service_test_last_error = (int32_t)ERROR_OUTOFMEMORY;
    free(exe_full);
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    free(stdout_buf);
    free(stderr_buf);
    return 0;
  }
  full_cmd[0] = L'\0';
  if (
    !metaeditor_service_append_wstring(full_cmd, full_cmd_len + 1, L"\"") ||
    !metaeditor_service_append_wstring(full_cmd, full_cmd_len + 1, exe_full) ||
    !metaeditor_service_append_wstring(full_cmd, full_cmd_len + 1, L"\" ") ||
    !metaeditor_service_append_wstring(full_cmd, full_cmd_len + 1, cmd_buf)
  ) {
    metaeditor_service_test_last_error = (int32_t)ERROR_INSUFFICIENT_BUFFER;
    free(full_cmd);
    free(exe_full);
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    free(stdout_buf);
    free(stderr_buf);
    return 0;
  }

  DWORD cwd_full_len = GetFullPathNameW(cwd_buf, 0, NULL, NULL);
  if (cwd_full_len == 0) {
    metaeditor_service_test_last_error = (int32_t)GetLastError();
    free(full_cmd);
    free(exe_full);
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    free(stdout_buf);
    free(stderr_buf);
    return 0;
  }
  WCHAR *cwd_full = (WCHAR *)malloc((cwd_full_len + 1) * sizeof(WCHAR));
  if (cwd_full == NULL) {
    metaeditor_service_test_last_error = (int32_t)ERROR_OUTOFMEMORY;
    free(full_cmd);
    free(exe_full);
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    free(stdout_buf);
    free(stderr_buf);
    return 0;
  }
  if (GetFullPathNameW(cwd_buf, cwd_full_len + 1, cwd_full, NULL) == 0) {
    metaeditor_service_test_last_error = (int32_t)GetLastError();
    free(cwd_full);
    free(full_cmd);
    free(exe_full);
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    free(stdout_buf);
    free(stderr_buf);
    return 0;
  }

  HANDLE stdin_handle = metaeditor_service_open_inheritable_null();
  HANDLE stdout_handle = metaeditor_service_open_inheritable_file(stdout_buf);
  HANDLE stderr_handle = metaeditor_service_open_inheritable_file(stderr_buf);
  free(stdout_buf);
  free(stderr_buf);
  if (
    stdin_handle == INVALID_HANDLE_VALUE ||
    stdout_handle == INVALID_HANDLE_VALUE ||
    stderr_handle == INVALID_HANDLE_VALUE
  ) {
    metaeditor_service_test_last_error = (int32_t)GetLastError();
    if (stdin_handle != INVALID_HANDLE_VALUE) CloseHandle(stdin_handle);
    if (stdout_handle != INVALID_HANDLE_VALUE) CloseHandle(stdout_handle);
    if (stderr_handle != INVALID_HANDLE_VALUE) CloseHandle(stderr_handle);
    free(cwd_full);
    free(full_cmd);
    free(exe_full);
    free(exe_buf);
    free(cmd_buf);
    free(cwd_buf);
    return 0;
  }

  STARTUPINFOW startup_info;
  PROCESS_INFORMATION process_info;
  ZeroMemory(&startup_info, sizeof(startup_info));
  ZeroMemory(&process_info, sizeof(process_info));
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESTDHANDLES;
  startup_info.hStdInput = stdin_handle;
  startup_info.hStdOutput = stdout_handle;
  startup_info.hStdError = stderr_handle;

  BOOL ok = CreateProcessW(
    exe_full,
    full_cmd,
    NULL,
    NULL,
    TRUE,
    CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
    NULL,
    cwd_full,
    &startup_info,
    &process_info
  );

  CloseHandle(stdin_handle);
  CloseHandle(stdout_handle);
  CloseHandle(stderr_handle);
  free(cwd_full);
  free(full_cmd);
  free(exe_full);
  free(exe_buf);
  free(cmd_buf);
  free(cwd_buf);

  if (!ok) {
    metaeditor_service_test_last_error = (int32_t)GetLastError();
    return 0;
  }

  CloseHandle(process_info.hThread);
  struct metaeditor_service_test_process *proc =
    (struct metaeditor_service_test_process *)malloc(sizeof(struct metaeditor_service_test_process));
  if (proc == NULL) {
    TerminateProcess(process_info.hProcess, 1);
    CloseHandle(process_info.hProcess);
    return 0;
  }
  proc->process = process_info.hProcess;
  return (uint64_t)(uintptr_t)proc;
}

int32_t metaeditor_service_test_last_spawn_error() {
  return metaeditor_service_test_last_error;
}

int32_t metaeditor_service_test_try_wait(
  uint64_t proc_handle,
  int32_t *exit_code
) {
  struct metaeditor_service_test_process *proc =
    (struct metaeditor_service_test_process *)(uintptr_t)proc_handle;
  if (proc == NULL || exit_code == NULL) {
    return 0;
  }
  DWORD code = 0;
  if (!GetExitCodeProcess(proc->process, &code)) {
    return 0;
  }
  if (code == STILL_ACTIVE) {
    return 0;
  }
  *exit_code = (int32_t)code;
  return 1;
}

void metaeditor_service_test_terminate(uint64_t proc_handle) {
  struct metaeditor_service_test_process *proc =
    (struct metaeditor_service_test_process *)(uintptr_t)proc_handle;
  if (proc == NULL) {
    return;
  }
  TerminateProcess(proc->process, 1);
  WaitForSingleObject(proc->process, 5000);
}

void metaeditor_service_test_free(uint64_t proc_handle) {
  struct metaeditor_service_test_process *proc =
    (struct metaeditor_service_test_process *)(uintptr_t)proc_handle;
  if (proc == NULL) {
    return;
  }
  CloseHandle(proc->process);
  free(proc);
}

int32_t metaeditor_service_retain_state_file(moonbit_string_t path) {
  WCHAR *buffer = metaeditor_service_copy_wstring(path);
  if (buffer == NULL) {
    return 0;
  }
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
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <sys/select.h>
#include <sys/socket.h>
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

int32_t metaeditor_service_port_ready(int32_t port) {
  if (port <= 0) {
    return 0;
  }
  int sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock < 0) {
    return 0;
  }
  int flags = fcntl(sock, F_GETFL, 0);
  if (flags < 0 || fcntl(sock, F_SETFL, flags | O_NONBLOCK) < 0) {
    close(sock);
    return 0;
  }
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((uint16_t)port);
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  int rc = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
  if (rc < 0 && errno != EINPROGRESS) {
    close(sock);
    return 0;
  }
  fd_set write_set;
  FD_ZERO(&write_set);
  FD_SET(sock, &write_set);
  struct timeval timeout = { 0, 0 };
  rc = select(sock + 1, NULL, &write_set, NULL, &timeout);
  if (rc <= 0) {
    close(sock);
    return 0;
  }
  int so_error = 0;
  socklen_t so_len = sizeof(so_error);
  if (getsockopt(sock, SOL_SOCKET, SO_ERROR, &so_error, &so_len) < 0 || so_error != 0) {
    close(sock);
    return 0;
  }
  close(sock);
  return 1;
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
