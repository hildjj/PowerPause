//
//  main.m
//  PowerPause
//
//  Created by Joe Hildebrand on 3/8/17.
//  Copyright © 2017 Joe Hildebrand. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

void handle_sigchld(int sig) {
    int status = -1;
    waitpid((pid_t)(-1), &status, 0);
    exit(WEXITSTATUS(status));
}


BOOL isOnPower() {
    BOOL ret = NO;
    @autoreleasepool {
        CFTypeRef blob = IOPSCopyPowerSourcesInfo();
        if (blob == NULL) {
            NSLog(@"Error getting power sources");
        } else {
            NSArray *sources = (__bridge_transfer NSArray *) IOPSCopyPowerSourcesList(blob);
            for (id source in sources) {
                NSNumber *charged = source[@"Is Charged"];
                NSNumber *isCharging = source[@"Is Charging"];
                ret = ret || [charged boolValue] || [isCharging boolValue];
            }
            CFRelease(blob);
        }
    }
    return ret;
}

BOOL assertNoIdle(IOPMAssertionID *aid) {
    IOReturn asserted = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep,
                                                    kIOPMAssertionLevelOn,
                                                    CFSTR("PowerPause on power"),
                                                    aid);
    if (asserted != kIOReturnSuccess) {
        NSLog(@"ERROR: Idle assertion failed");
        return false;
    }
    return true;
}

BOOL clearNoIdle(IOPMAssertionID aid) {
    IOReturn asserted = IOPMAssertionRelease(aid);
    
    if (asserted != kIOReturnSuccess) {
        NSLog(@"ERROR: Idle unassertion failed");
        return false;
    }
    return true;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        NSLog(@"Command required");
        return 1;
    }
    // start the same type of shell that the user was just using
    char *sh = getenv("SHELL");
    if (!sh) {
        NSLog(@"SHELL not defined");
        return 1;
    }
    
    // this will be stdin for the shell
    // write the command to stdin, to avoid quote-y stuff, etc.
    int inp[2];
    if (pipe(inp) != 0) {
        perror("pipe");
        return 1;
    }
    
    // to my children, I leave death.
    // (pass along ctrl-c, etc)
    setpgid(0, 0);
    
    // when my children die, it breaks my heart.
    struct sigaction sa;
    sa.sa_handler = &handle_sigchld;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;
    if (sigaction(SIGCHLD, &sa, 0) == -1) {
        perror("sigaction");
        exit(1);
    }
    
    int child = -1;
    switch(child = fork()) {
        case -1:
            perror("fork");
            return 1;
        case 0: {
            // child
            char *child_args[] = {sh, NULL};
            close(STDIN_FILENO);
            dup(inp[0]);
            close(inp[1]);
            execv(sh, child_args);
            perror("execv");
            exit(1);
        }
    }
    
    // parent
    close(inp[0]);
    write(inp[1], "exec", 4);
    for (int i=1; i<argc; i++) {
        write(inp[1], " ", 1);
        write(inp[1], argv[i], strlen(argv[i]));
    }
    write(inp[1], "\n", 1);
    close(inp[1]);
    
    // keep checking power state
    struct timespec tim;
    tim.tv_sec = 0L;
    tim.tv_nsec = 500000000L;
    BOOL running = YES;
    IOPMAssertionID assertionID = -1;
    assertNoIdle(&assertionID);
    
    while (1) {
        if (isOnPower()) {
            if (!running) {
                running = YES;
                NSLog(@"CONTINUE");
                kill(child, SIGCONT);  // fg
                tim.tv_sec = 0L;
                assertNoIdle(&assertionID);
            }
        } else {
            if (running) {
                running = NO;
                NSLog(@"PAUSE");
                kill(child, SIGTSTP); // ctrl-z
                tim.tv_sec = 1L;
                clearNoIdle(assertionID);
                assertionID = -1;
            }
        }
        nanosleep(&tim, NULL);
    }

    return 0;
}
