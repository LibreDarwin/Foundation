/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * The legacy task surface is adapted from Cocotron/ravynOS NSTask by
 * Christopher J. W. Lloyd and Markus Hitter, used under its MIT license.
 * Process creation and descriptor wiring are implemented with Darwin's
 * posix_spawn API rather than ravynOS's NSPlatform abstraction.
 */

#import <Foundation/NSTask.h>
#import <Foundation/NSNotificationCenter.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

NSString * const NSTaskDidTerminateNotification = @"NSTaskDidTerminateNotification";

#if __has_feature(objc_arc)
#define NSTASK_CF(type, value) ((__bridge type)(value))
#else
#define NSTASK_CF(type, value) ((type)(value))
#endif

static char *_NSTaskCString(NSString *string) {
    const char *source = [string UTF8String];
    if (source == NULL) return NULL;
    size_t length = strlen(source);
    char *copy = (char *)malloc(length + 1);
    if (copy != NULL) memcpy(copy, source, length + 1);
    return copy;
}

static int _NSTaskDescriptor(id channel, BOOL input) {
    if ([channel isKindOfClass:[NSFileHandle class]]) {
        return [(NSFileHandle *)channel fileDescriptor];
    }
    if ([channel isKindOfClass:[NSPipe class]]) {
        NSPipe *pipe = (NSPipe *)channel;
        return input ? [[pipe fileHandleForReading] fileDescriptor]
                     : [[pipe fileHandleForWriting] fileDescriptor];
    }
    return -1;
}

static char **_NSTaskEnvironment(NSDictionary *environment) {
    if (environment == nil) return environ;
    NSUInteger count = [environment count];
    char **result = (char **)calloc(count + 1, sizeof(*result));
    if (result == NULL) return NULL;
    NSArray *keys = [environment allKeys];
    for (NSUInteger i = 0; i < count; i++) {
        NSString *key = [keys objectAtIndex:i];
        NSString *value = [environment objectForKey:key];
        const char *keyString = [key UTF8String];
        const char *valueString = [value UTF8String];
        if (keyString == NULL || valueString == NULL) continue;
        size_t length = strlen(keyString) + strlen(valueString) + 2;
        result[i] = (char *)malloc(length);
        if (result[i] != NULL) snprintf(result[i], length, "%s=%s", keyString, valueString);
    }
    return result;
}

static void _NSTaskFreeEnvironment(char **environment) {
    if (environment == NULL || environment == environ) return;
    for (char **entry = environment; *entry != NULL; entry++) free(*entry);
    free(environment);
}

@implementation NSTask

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _terminationStatus = -1;
        _terminationReason = NSTaskTerminationReasonExit;
    }
    return self;
}

- (NSString *)launchPath { return _launchPath; }
- (void)setLaunchPath:(NSString *)value {
#if __has_feature(objc_arc)
    _launchPath = [value copy];
#else
    [_launchPath release]; _launchPath = [value copy];
#endif
}
- (NSArray *)arguments { return _arguments; }
- (void)setArguments:(NSArray *)value {
#if __has_feature(objc_arc)
    _arguments = [value copy];
#else
    [_arguments release]; _arguments = [value copy];
#endif
}
- (NSDictionary *)environment { return _environment; }
- (void)setEnvironment:(NSDictionary *)value {
#if __has_feature(objc_arc)
    _environment = [value copy];
#else
    [_environment release]; _environment = [value copy];
#endif
}
- (NSString *)currentDirectoryPath { return _currentDirectoryPath; }
- (void)setCurrentDirectoryPath:(NSString *)value {
#if __has_feature(objc_arc)
    _currentDirectoryPath = [value copy];
#else
    [_currentDirectoryPath release]; _currentDirectoryPath = [value copy];
#endif
}
- (id)standardInput { return _standardInput; }
- (void)setStandardInput:(id)value {
#if __has_feature(objc_arc)
    _standardInput = value;
#else
    [_standardInput release]; _standardInput = [value retain];
#endif
}
- (id)standardOutput { return _standardOutput; }
- (void)setStandardOutput:(id)value {
#if __has_feature(objc_arc)
    _standardOutput = value;
#else
    [_standardOutput release]; _standardOutput = [value retain];
#endif
}
- (id)standardError { return _standardError; }
- (void)setStandardError:(id)value {
#if __has_feature(objc_arc)
    _standardError = value;
#else
    [_standardError release]; _standardError = [value retain];
#endif
}

- (BOOL)launchAndReturnError:(NSError **)error {
    if (_hasLaunched || _launchPath == nil) {
        if (error) *error = nil;
        return NO;
    }
    _hasLaunched = YES;

    NSUInteger argumentCount = [_arguments count];
    char **argv = (char **)calloc(argumentCount + 2, sizeof(*argv));
    if (argv == NULL) return NO;
    argv[0] = _NSTaskCString(_launchPath);
    for (NSUInteger i = 0; i < argumentCount; i++) {
        argv[i + 1] = _NSTaskCString([_arguments objectAtIndex:i]);
    }
    argv[argumentCount + 1] = NULL;

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    int descriptors[3] = {
        _NSTaskDescriptor(_standardInput, YES),
        _NSTaskDescriptor(_standardOutput, NO),
        _NSTaskDescriptor(_standardError, NO)
    };
    for (int i = 0; i < 3; i++) {
        if (descriptors[i] >= 0) posix_spawn_file_actions_adddup2(&actions, descriptors[i], i);
    }

    char *directory = _NSTaskCString(_currentDirectoryPath);
    if (directory != NULL) {
        posix_spawn_file_actions_addchdir_np(&actions, directory);
    }

    char **environment = _NSTaskEnvironment(_environment);
    int status = environment == NULL ? ENOMEM :
        posix_spawn(&_processIdentifier, argv[0], &actions, NULL, argv, environment);
    posix_spawn_file_actions_destroy(&actions);
    free(directory);
    _NSTaskFreeEnvironment(environment);
    for (NSUInteger i = 0; i < argumentCount + 1; i++) free(argv[i]);
    free(argv);

    if (status != 0) {
        _processIdentifier = 0;
        if (error) *error = nil;
        return NO;
    }
    _running = YES;
    return YES;
}

- (void)launch { (void)[self launchAndReturnError:NULL]; }

+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments {
    NSTask *task = [[self alloc] init];
    task.launchPath = path;
    task.arguments = arguments;
    [task launch];
#if __has_feature(objc_arc)
    return task;
#else
    return [task autorelease];
#endif
}

- (void)waitUntilExit {
    if (!_hasLaunched || !_running) return;
    int status = 0;
    while (waitpid(_processIdentifier, &status, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(status)) {
        _terminationStatus = WEXITSTATUS(status);
        _terminationReason = NSTaskTerminationReasonExit;
    } else if (WIFSIGNALED(status)) {
        _terminationStatus = WTERMSIG(status);
        _terminationReason = NSTaskTerminationReasonUncaughtSignal;
    }
    _running = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTaskDidTerminateNotification object:self];
}

- (void)interrupt { if (_running) kill(_processIdentifier, SIGINT); }
- (void)terminate { if (_running) kill(_processIdentifier, SIGTERM); }
- (BOOL)suspend { return _running && kill(_processIdentifier, SIGSTOP) == 0; }
- (BOOL)resume { return _running && kill(_processIdentifier, SIGCONT) == 0; }
- (int)processIdentifier { return (int)_processIdentifier; }
- (BOOL)isRunning { return _running; }
- (int)terminationStatus { return _terminationStatus; }
- (NSTaskTerminationReason)terminationReason { return _terminationReason; }

- (void)dealloc {
#if !__has_feature(objc_arc)
    [_launchPath release]; [_arguments release]; [_environment release];
    [_currentDirectoryPath release]; [_standardInput release];
    [_standardOutput release]; [_standardError release];
    [super dealloc];
#endif
}

@end
