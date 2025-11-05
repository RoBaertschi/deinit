package deinit

import "base:runtime"

import "core:c"
import "core:fmt"
import "core:strings"
import "core:sys/posix"

import os "core:os/os2"

Mount_Flag :: enum c.ulong {
    RDONLY,
    NOSUID,
    NODEV,
    NOEXEC,
    SYNCHRONOUS,
    REMOUNT,
    MANDLOCK,
    DIRSYNC,
    NOSYMFOLLOW,
    _,
    NOATIME,
    NODIRATIME,
    BIND,
    MOVE,
    REC,
    SILENT,
    POSIXACL,
    UNBINDABLE,
    PRIVATE,
    SLAVE,
    SHARED,
    RELATIME,
    KERNMOUNT,
    I_VERSION,
    STRICTATIME,
    LAZYTIME,
    _, _, _, _,
    ACTIVE,
    NOUSER,
}

Mount_Flags :: bit_set[Mount_Flag; c.ulong]

foreign {
    mount :: proc(source: cstring, target: cstring, filesystemtype: cstring, mountflags: Mount_Flags, data: rawptr) -> c.int ---
}


INIT_COMMAND := []cstring{ "/sbin/agetty", "--noclear", "38400", "tty1", "linux", nil }

sigmap := []struct{ sig: posix.Signal, handler: #type proc() }{
    { .SIGUSR1, proc() { spawn({ "/bin/rc.shutdown", "poweroff", nil }) } },
    { .SIGCHLD, sigreap },
    { .SIGALRM, sigreap },
    { .SIGINT,  proc() { spawn({ "/bin/rc.shutdown", "reboot", nil }) } },
}

set: posix.sigset_t

// returns a list of all mount points
read_mounts :: proc(allocator := context.allocator) -> (mounts: [dynamic]string, ok: bool) {
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    mounts_file, err := os.open("/proc/mounts")
    if err != nil {
        return
    }

    mounts_txt: []byte
    mounts_txt, err = os.read_entire_file_from_file(mounts_file, allocator)
    if err != nil {
        return
    }

    lines, alloc_err := strings.split(string(mounts_txt), "\n", context.temp_allocator)
    if alloc_err != nil {
        return
    }

    mounts = make([dynamic]string, allocator = allocator)
    defer if !ok { delete(mounts) }

    line_iter: for line in lines {
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        tabs_removed: string
        tabs_removed, _ = strings.replace_all(line, "\t", " ", context.temp_allocator)

        splitted: []string
        splitted, alloc_err = strings.split(line, " ", context.temp_allocator)

        for split, i in splitted {
            if i > 0 && split != "" {
                cloned: string
                cloned, alloc_err = strings.clone(split, allocator = allocator)
                if alloc_err != nil {
                    return
                }
                _, alloc_err = append(&mounts, cloned)
                if alloc_err != nil {
                    return
                }
                continue line_iter
            }
        }

        // TODO(robin): Warn about broken line in /proc/mounts
    }

    ok = true
    return
}

try_mount :: proc(mounts: []string, from: cstring, to: cstring, type: cstring, flags: Mount_Flags = {}, data: cstring = nil) {
    flags := flags

    if .REMOUNT not_in flags {
        for mount in mounts {
            if mount == string(to) {
                flags += { .REMOUNT }
                break
            }
        }
    }

    if mount(from, to, type, flags, rawptr(data)) < 0 {
        posix.perror("mount")
    }
}

main :: proc() {
    fmt.println("Say hi to deinit!")

    if posix.getpid() != 1 {
        os.exit(1)
    }

    if os.chdir("/") != nil {
        // TODO(robin): fatal
        os.exit(1)
    }

    posix.sigfillset(&set)
    posix.sigprocmask(.BLOCK, &set, nil)

    try_mount({}, "proc", "/proc", "proc")

    mounts, mounts_ok := read_mounts()
    if !mounts_ok {
        // TODO(robin): prober logging
    }

    fmt.println("Mounts:", mounts[:])

    try_mount(mounts[:], "dev", "/dev", "devtmpfs", data = "mode=0755")
    try_mount(mounts[:], "sys", "/sys", "sysfs")
    //
    // spawn({ "/bin/mount", "-t", "devtmpfs", "-o", "remount,mode=0755", "dev", "/dev", nil })
    // spawn({ "/bin/mount", "-t", "sysfs", "sys", "/sys", nil })
    // spawn({ "/bin/mount", "-t", "proc", "proc", "/proc", nil })

    spawn(INIT_COMMAND)
    for {
        posix.alarm(30)
        sig: posix.Signal
        posix.sigwait(&set, &sig)

        for m in sigmap {
            if m.sig == sig {
                m.handler()
                break
            }
        }
    }
    unreachable()
}

sigreap :: proc() {
    for posix.waitpid(-1, nil, { .NOHANG }) > 0 {}

    posix.alarm(30)
}

spawn :: proc(args: []cstring) {
    switch posix.fork() {
    case 0:
        posix.sigprocmask(.UNBLOCK, &set, nil)
        posix.setsid()
        posix.execvp(args[0], raw_data(args))
        posix.perror("execvp")
        os.exit(1)
    case -1:
        // TODO(robin): log error
        posix.perror("fork")
    }
}
