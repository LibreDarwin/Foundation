/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * This header mirrors Apple's NSKeyValueObserving.h.  Only the surface the
 * port implements is declared; the deprecated AppKit-only customization
 * category and the NSArray ordered-observer convenience category are omitted.
 */

#ifndef NSKeyValueObserving_h
#define NSKeyValueObserving_h

#import <Foundation/NSObject.h>
#import <Foundation/NSObjCRuntime.h>

@class NSArray, NSSet, NSDictionary, NSIndexSet, NSString;

FOUNDATION_EXPORT NSString *const NSKeyValueChangeKindKey;
FOUNDATION_EXPORT NSString *const NSKeyValueChangeNewKey;
FOUNDATION_EXPORT NSString *const NSKeyValueChangeOldKey;
FOUNDATION_EXPORT NSString *const NSKeyValueChangeIndexesKey;
FOUNDATION_EXPORT NSString *const NSKeyValueChangeNotificationIsPriorKey;

typedef NS_OPTIONS(NSUInteger, NSKeyValueObservingOptions) {
    NSKeyValueObservingOptionNew = 0x01,
    NSKeyValueObservingOptionOld = 0x02,
    NSKeyValueObservingOptionInitial = 0x04,
    NSKeyValueObservingOptionPrior = 0x08
};

typedef NS_ENUM(NSUInteger, NSKeyValueChange) {
    NSKeyValueChangeSetting = 1,
    NSKeyValueChangeInsertion = 2,
    NSKeyValueChangeRemoval = 3,
    NSKeyValueChangeReplacement = 4
};

typedef NS_ENUM(NSUInteger, NSKeyValueSetMutationKind) {
    NSKeyValueUnionSetMutation = 1,
    NSKeyValueMinusSetMutation = 2,
    NSKeyValueIntersectSetMutation = 3,
    NSKeyValueSetSetMutation = 4
};

@interface NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(nullable NSString *)keyPath
                      ofObject:(nullable id)object
                        change:(nullable NSDictionary *)change
                       context:(nullable void *)context;

- (void)addObserver:(NSObject *)observer
         forKeyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options
            context:(nullable void *)context;

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath;
- (void)removeObserver:(NSObject *)observer
            forKeyPath:(NSString *)keyPath
               context:(nullable void *)context;

- (void)willChangeValueForKey:(NSString *)key;
- (void)didChangeValueForKey:(NSString *)key;

- (void)willChange:(NSKeyValueChange)change
   valuesAtIndexes:(NSIndexSet *)indexes
            forKey:(NSString *)key;
- (void)didChange:(NSKeyValueChange)change
  valuesAtIndexes:(NSIndexSet *)indexes
           forKey:(NSString *)key;

- (void)willChangeValueForKey:(NSString *)key
               withSetMutation:(NSKeyValueSetMutationKind)mutation
                  usingObjects:(NSSet *)objects;
- (void)didChangeValueForKey:(NSString *)key
              withSetMutation:(NSKeyValueSetMutationKind)mutation
                 usingObjects:(NSSet *)objects;

- (void)setObservationInfo:(nullable void *)newInfo;
- (nullable void *)observationInfo;

@end

@interface NSObject (NSKeyValueObservingCustomization)

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key;
+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key;
+ (void)setKeys:(NSArray *)keys triggerChangeNotificationsForDependentKey:(NSString *)dependentKey;

@end

#endif /* NSKeyValueObserving_h */