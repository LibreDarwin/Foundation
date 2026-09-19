/*
 * Copyright (C) 2026, PureDarwin Project.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#ifndef NSTask_h
#define NSTask_h

#import <Foundation/NSObject.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSPipe.h>

typedef NS_ENUM(NSInteger, NSTaskTerminationReason) {
    NSTaskTerminationReasonExit = 1,
    NSTaskTerminationReasonUncaughtSignal = 2
};

FOUNDATION_EXPORT NSString * const NSTaskDidTerminateNotification;

@interface NSTask : NSObject {
    NSString *_launchPath;
    NSArray *_arguments;
    NSDictionary *_environment;
    NSString *_currentDirectoryPath;
    id _standardInput;
    id _standardOutput;
    id _standardError;
    pid_t _processIdentifier;
    int _terminationStatus;
    NSTaskTerminationReason _terminationReason;
    BOOL _running;
    BOOL _hasLaunched;
}

- (instancetype)init;

@property (copy) NSString *launchPath;
@property (copy) NSArray *arguments;
@property (copy) NSDictionary *environment;
@property (copy) NSString *currentDirectoryPath;
@property (retain) id standardInput;
@property (retain) id standardOutput;
@property (retain) id standardError;

- (void)launch;
- (BOOL)launchAndReturnError:(NSError **)error;
+ (NSTask *)launchedTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments;

- (void)interrupt;
- (void)terminate;
- (BOOL)suspend;
- (BOOL)resume;
- (void)waitUntilExit;

@property (readonly) int processIdentifier;
@property (readonly, getter=isRunning) BOOL running;
@property (readonly) int terminationStatus;
@property (readonly) NSTaskTerminationReason terminationReason;

@end

#endif /* NSTask_h */
