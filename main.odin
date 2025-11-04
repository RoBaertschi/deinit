package deinit

import os "core:os/os2"

import "core:sys/posix"

main :: proc() {
    if posix.getpid() != 1 {
        os.exit(1)
    }

    if os.chdir("/") != nil {
        // TODO(robin): fatal
        os.exit(1)
    }

    set: posix.sigset_t
    posix.sigfillset(&set)
    posix.sigprocmask(.BLOCK, &set, nil)
    
}
