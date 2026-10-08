/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Key-Value Observing.  This implements the manual half of Apple's KVO: the
 * observing API, the change-notification machinery driven by
 * -willChangeValueForKey:/-didChangeValueForKey: (and the ordered/set-mutation
 * variants), dependent-key propagation, and the customization hooks.  The
 * automatic half (isa-swizzling to a per-class NSKVONotifying_ subclass) is
 * intentionally not implemented yet; classes must opt out of automatic
 * notification and drive the change methods themselves.
 */

#import <Foundation/NSKeyValueObserving.h>
#import <Foundation/NSKeyValueCoding.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSSet.h>
#import <Foundation/NSIndexSet.h>
#import <Foundation/NSString.h>
#import <Foundation/NSNumber.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSException.h>
#import <objc/runtime.h>

NSString *const NSKeyValueChangeKindKey = @"kind";
NSString *const NSKeyValueChangeNewKey = @"new";
NSString *const NSKeyValueChangeOldKey = @"old";
NSString *const NSKeyValueChangeIndexesKey = @"indexes";
NSString *const NSKeyValueChangeNotificationIsPriorKey = @"notificationIsPrior";

static char kNSKVOInfoKey;
static char kNSKVOExternalInfoKey;

#pragma mark - Internal bookkeeping

@interface _NSKVORegistration : NSObject
@property (nonatomic, assign) id observer;
@property (nonatomic, copy) NSString *keyPath;
@property (nonatomic, assign) NSKeyValueObservingOptions options;
@property (nonatomic, assign) void *context;
@property (nonatomic, strong) NSSet *dependencies;
@end

@implementation _NSKVORegistration
@end

enum {
    _NSKVOPendingSetting = 0,
    _NSKVOPendingOrdered = 1,
    _NSKVOPendingSet = 2,
};

@interface _NSKVOPending : NSObject
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, assign) NSInteger kind;
@property (nonatomic, strong) NSArray *targets;
@property (nonatomic, strong) id oldValues;
@property (nonatomic, strong) NSIndexSet *indexes;
@property (nonatomic, strong) id objects;
@property (nonatomic, strong) id oldValue;
@end

@implementation _NSKVOPending
@end

@interface _NSKVOInfo : NSObject
@property (nonatomic, strong) NSMutableArray<_NSKVORegistration *> *registrations;
@property (nonatomic, strong) NSMutableArray<_NSKVOPending *> *pending;
@end

@implementation _NSKVOInfo
@end


static NSString *_NSKVONotifyingClassNameForClass(Class cls) {
    return [NSString stringWithFormat:@"NSKVONotifying_%@", NSStringFromClass(cls)];
}

static void _NSKVOInjectSetter(Class kvoClass, Class originalClass, SEL setterSel, SEL getterSel, NSString *keyPath) {
    Method origMethod = class_getInstanceMethod(originalClass, setterSel);
    if (origMethod == NULL) {
        return;
    }
    const char *types = method_getTypeEncoding(origMethod);
    IMP origIMP = method_getImplementation(origMethod);
    
    IMP newIMP = imp_implementationWithBlock(^(id self, id newValue) {
        [self willChangeValueForKey:keyPath];
        ((void (*)(id, SEL, id))origIMP)(self, setterSel, newValue);
        [self didChangeValueForKey:keyPath];
    });
    class_addMethod(kvoClass, setterSel, newIMP, types);
}


static _NSKVOInfo *NSKVOInfoForObject(id object, BOOL create) {
    _NSKVOInfo *info = objc_getAssociatedObject(object, &kNSKVOInfoKey);
    if (info == nil && create) {
        info = [[_NSKVOInfo alloc] init];
        info.registrations = [NSMutableArray array];
        info.pending = [NSMutableArray array];
        objc_setAssociatedObject(object, &kNSKVOInfoKey, info, OBJC_ASSOCIATION_RETAIN);
    }
    return info;
}


static Class _NSKVOClassForObject(id object) {
    Class cls = object_getClass(object);
    if ([NSStringFromClass(cls) hasPrefix:@"NSKVONotifying_"]) {
        return cls;
    }
    return NULL;
}

static Class _NSKVOEnsureSubclass(id object, NSString *keyPath) {
    Class cls = object_getClass(object);
    NSString *className = NSStringFromClass(cls);
    if ([className hasPrefix:@"NSKVONotifying_"]) {
        return cls;
    }
    // Check if auto-notifies for this key
    if (![[cls class] automaticallyNotifiesObserversForKey:keyPath]) {
        return cls;
    }
    NSString *kvoClassName = _NSKVONotifyingClassNameForClass(cls);
    Class kvoClass = objc_getClass([kvoClassName UTF8String]);
    if (kvoClass == Nil) {
        kvoClass = objc_allocateClassPair(cls, [kvoClassName UTF8String], 0);
        if (kvoClass == Nil) {
            return cls;
        }
        // Override -class to return original class
        Method classMethod = class_getInstanceMethod([NSObject class], @selector(class));
        IMP classIMP = imp_implementationWithBlock(^(id self) {
            return class_getSuperclass(object_getClass(self));
        });
        const char *classTypes = method_getTypeEncoding(classMethod);
        class_addMethod(kvoClass, @selector(class), classIMP, classTypes);
        // Override -dealloc to be careful? Not strictly necessary for basic cases
        objc_registerClassPair(kvoClass);
    }
    // Swizzle setter if it's a simple property setter
    // Try common setter names: set<Key>: set<Key>:
    NSString *capitalized = nil;
    if ([keyPath length] > 0) {
        capitalized = [NSString stringWithFormat:@"%@%@", [[keyPath substringToIndex:1] uppercaseString], [keyPath substringFromIndex:1]];
    }
    SEL setterSel = NSSelectorFromString([NSString stringWithFormat:@"set%@:", capitalized]);
    SEL getterSel = NSSelectorFromString(keyPath);
    // Only inject if setter exists on original class
    if (class_getInstanceMethod(cls, setterSel)) {
        _NSKVOInjectSetter(kvoClass, cls, setterSel, getterSel, keyPath);
    }
    object_setClass(object, kvoClass);
    return kvoClass;
}


static BOOL NSKVOHasObservers(id object, NSString *keyPath) {
    _NSKVOInfo *info = NSKVOInfoForObject(object, NO);
    if (info == nil) {
        return NO;
    }
    for (_NSKVORegistration *reg in info.registrations) {
        if ([reg.keyPath isEqualToString:keyPath]) {
            return YES;
        }
    }
    return NO;
}

/* Deprecated dependent-key registry: class name -> dependent key -> key set. */
static NSMutableDictionary *NSKVODependentRegistry(void) {
    static NSMutableDictionary *registry = nil;
    if (registry == nil) {
        registry = [[NSMutableDictionary alloc] init];
    }
    return registry;
}

static NSString *NSKVOCapitalizedKey(NSString *key) {
    if ([key length] == 0) {
        return key;
    }
    NSString *head = [[key substringToIndex:1] uppercaseString];
    return [head stringByAppendingString:[key substringFromIndex:1]];
}

/* Direct dependent keys declared for a class, via the accessor or the
 * deprecated registry. */
static NSSet *NSKVODirectDependentKeys(Class cls, NSString *key) {
    NSString *selectorName = [NSString stringWithFormat:@"keyPathsForValuesAffecting%@",
                                                       NSKVOCapitalizedKey(key)];
    SEL selector = NSSelectorFromString(selectorName);
    if ([cls respondsToSelector:selector]) {
        IMP imp = [cls methodForSelector:selector];
        id result = ((id (*)(id, SEL, NSString *))imp)(cls, selector, key);
        if ([result isKindOfClass:[NSSet class]]) {
            return result;
        }
        if ([result isKindOfClass:[NSArray class]]) {
            return [NSSet setWithArray:result];
        }
        return [NSSet set];
    }

    NSDictionary *forClass = [NSKVODependentRegistry() objectForKey:NSStringFromClass(cls)];
    NSSet *registered = [forClass objectForKey:key];
    return registered != nil ? registered : [NSSet set];
}

/* Transitive closure of the dependent keys for ``key'', so a single lookup
 * during add/remove captures indirect dependencies. */
static NSSet *NSKVOTransitiveDependencies(Class cls, NSString *key) {
    NSMutableSet *result = [[NSMutableSet alloc] init];
    NSMutableArray *stack = [NSMutableArray array];
    [stack addObject:key];
    while ([stack count] > 0) {
        NSString *current = [stack lastObject];
        [stack removeLastObject];
        for (NSString *dep in NSKVODirectDependentKeys(cls, current)) {
            if (![result containsObject:dep]) {
                [result addObject:dep];
                [stack addObject:dep];
            }
        }
    }
    return result;
}

/* Keys whose observers must be told when `key` changes: the key itself plus
 * any observed key path that transitively depends on it. */
static NSSet *NSKVOAffectedKeys(id object, NSString *key) {
    NSMutableSet *targets = [[NSMutableSet alloc] init];
    [targets addObject:key];
    _NSKVOInfo *info = NSKVOInfoForObject(object, NO);
    for (_NSKVORegistration *reg in info.registrations) {
        if ([reg.keyPath isEqualToString:key]) {
            continue;
        }
        if ([reg.dependencies containsObject:key]) {
            [targets addObject:reg.keyPath];
        }
    }
    return targets;
}

#pragma mark - Notification delivery

static void NSKVONotifyKey(id observed, NSString *keyPath, NSInteger kind,
                           id oldValue, id newValue, NSIndexSet *indexes, BOOL prior) {
    _NSKVOInfo *info = NSKVOInfoForObject(observed, NO);
    for (_NSKVORegistration *reg in info.registrations) {
        if (![reg.keyPath isEqualToString:keyPath]) {
            continue;
        }
        if (prior && !(reg.options & NSKeyValueObservingOptionPrior)) {
            continue;
        }

        NSMutableDictionary *change = [NSMutableDictionary dictionary];
        [change setObject:@(kind) forKey:NSKeyValueChangeKindKey];
        if (prior) {
            [change setObject:@YES forKey:NSKeyValueChangeNotificationIsPriorKey];
        }
        if (oldValue != nil && (reg.options & NSKeyValueObservingOptionOld)) {
            [change setObject:oldValue forKey:NSKeyValueChangeOldKey];
        }
        if (!prior && newValue != nil && (reg.options & NSKeyValueObservingOptionNew)) {
            [change setObject:newValue forKey:NSKeyValueChangeNewKey];
        }
        if (indexes != nil) {
            [change setObject:indexes forKey:NSKeyValueChangeIndexesKey];
        }
        [reg.observer observeValueForKeyPath:keyPath ofObject:observed change:change context:reg.context];
    }
}

static NSArray *NSKVOObjectValueForKey(id object, NSString *key) {
    id value = [object valueForKey:key];
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static NSArray *NSKVOSubarrayAtIndexes(NSArray *array, NSIndexSet *indexes) {
    NSMutableArray *result = [NSMutableArray array];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        if (idx < [array count]) {
            [result addObject:[array objectAtIndex:idx]];
        }
    }];
    return result;
}

#pragma mark - NSObject KVO

@implementation NSObject (NSKeyValueObserving)

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {
    [NSException raise:NSInternalInconsistencyException
                format:@"%@: An -observeValueForKeyPath:ofObject:change:context: message "
                       @"was received but not handled.\nKey path: %@\nObserved object: %@\n"
                       @"Change: %@\nContext: %p",
                       self, keyPath, object, change, context];
}

- (void)addObserver:(NSObject *)observer
         forKeyPath:(NSString *)keyPath
            options:(NSKeyValueObservingOptions)options
            context:(void *)context {
    if (observer == nil || keyPath == nil) {
        [NSException raise:NSInvalidArgumentException
                    format:@"-addObserver:forKeyPath:options:context: observer and key path "
                           @"must not be nil."];
    }

    // Ensure automatic KVO subclass if applicable
    _NSKVOEnsureSubclass(self, keyPath);
    
    _NSKVOInfo *info = NSKVOInfoForObject(self, YES);
    _NSKVORegistration *reg = [[_NSKVORegistration alloc] init];
    reg.observer = observer;
    reg.keyPath = keyPath;
    reg.options = options;
    reg.context = context;

    NSMutableSet *dependencies = [[NSMutableSet alloc] init];
    NSMutableArray *frontier = [NSMutableArray array];
    [frontier addObject:keyPath];
    while ([frontier count] > 0) {
        NSString *key = [frontier objectAtIndex:0];
        [frontier removeObjectAtIndex:0];
        for (NSString *dep in NSKVODirectDependentKeys(object_getClass(self), key)) {
            if (![dependencies containsObject:dep]) {
                [dependencies addObject:dep];
                [frontier addObject:dep];
            }
        }
    }
    reg.dependencies = dependencies;

    [info.registrations addObject:reg];

    if (options & NSKeyValueObservingOptionInitial) {
        NSMutableDictionary *change = [NSMutableDictionary dictionary];
        [change setObject:@(NSKeyValueChangeSetting) forKey:NSKeyValueChangeKindKey];
        id newValue = [self valueForKey:keyPath];
        if (newValue != nil && (options & NSKeyValueObservingOptionNew)) {
            [change setObject:newValue forKey:NSKeyValueChangeNewKey];
        }
        [observer observeValueForKeyPath:keyPath ofObject:self change:change context:context];
    }
}

- (void)removeObserver:(NSObject *)observer forKeyPath:(NSString *)keyPath {
    [self removeObserver:observer forKeyPath:keyPath context:NULL];
}

- (void)removeObserver:(NSObject *)observer
            forKeyPath:(NSString *)keyPath
               context:(void *)context {
    _NSKVOInfo *info = NSKVOInfoForObject(self, NO);
    NSMutableArray *kept = [NSMutableArray array];
    NSMutableArray *removed = [NSMutableArray array];
    for (_NSKVORegistration *reg in info.registrations) {
        if (reg.observer == observer && [reg.keyPath isEqualToString:keyPath] &&
            (context == NULL || reg.context == context)) {
            [removed addObject:reg];
        } else {
            [kept addObject:reg];
        }
    }
    if ([removed count] == 0) {
        [NSException raise:NSRangeException
                    format:@"Cannot remove an observer %@ for the key path \"%@\" from %@ "
                           @"because it is not registered as an observer.",
                           observer, keyPath, self];
    }
    info.registrations = kept;
    if ([kept count] == 0) {
        objc_setAssociatedObject(self, &kNSKVOInfoKey, nil, OBJC_ASSOCIATION_RETAIN);
    }
}

- (void)willChangeValueForKey:(NSString *)key {
    _NSKVOInfo *info = NSKVOInfoForObject(self, NO);
    if (info == nil || [info.registrations count] == 0) {
        return;
    }

    NSMutableSet *targets = NSKVOAffectedKeys(self, key);
    NSArray *targetList = [[targets allObjects] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableDictionary *oldValues = [NSMutableDictionary dictionary];
    for (NSString *target in targetList) {
        id oldValue = [self valueForKey:target];
        if (oldValue != nil) {
            [oldValues setObject:oldValue forKey:target];
        }
        NSKVONotifyKey(self, target, NSKeyValueChangeSetting, oldValue, nil, nil, YES);
    }

    _NSKVOPending *pending = [[_NSKVOPending alloc] init];
    pending.type = _NSKVOPendingSetting;
    pending.kind = NSKeyValueChangeSetting;
    pending.targets = targetList;
    pending.oldValues = oldValues;
    [info.pending addObject:pending];
}

- (void)didChangeValueForKey:(NSString *)key {
    _NSKVOInfo *info = NSKVOInfoForObject(self, NO);
    if (info == nil || [info.pending count] == 0) {
        return;
    }

    _NSKVOPending *pending = [info.pending lastObject];
    [info.pending removeLastObject];

    for (NSString *target in pending.targets) {
        id newValue = [self valueForKey:target];
        id oldValue = [pending.oldValues objectForKey:target];
        NSKVONotifyKey(self, target, NSKeyValueChangeSetting, oldValue, newValue, nil, NO);
    }
}

- (void)willChange:(NSKeyValueChange)change
   valuesAtIndexes:(NSIndexSet *)indexes
            forKey:(NSString *)key {
    _NSKVOInfo *info = NSKVOInfoForObject(self, NO);
    if (info == nil || !NSKVOHasObservers(self, key)) {
        return;
    }

    NSArray *array = NSKVOObjectValueForKey(self, key);
    NSArray *oldValues = array != nil ? NSKVOSubarrayAtIndexes(array, indexes) : [NSArray array];
    NSKVONotifyKey(self, key, change, oldValues, nil, indexes, YES);

    _NSKVOPending *pending = [[_NSKVOPending alloc] init];
    pending.type = _NSKVOPendingOrdered;
    pending.kind = change;
    pending.targets = @[ key ];
    pending.indexes = indexes;
    pending.oldValues = oldValues != nil ? oldValues : [NSArray array];
    [info.pending addObject:pending];
}

- (void)didChange:(NSKeyValueChange)change
  valuesAtIndexes:(NSIndexSet *)indexes
           forKey:(NSString *)key {
    _NSKVOInfo *info = NSKVOInfoForObject(self, NO);
    if (info == nil || [info.pending count] == 0) {
        return;
    }

    _NSKVOPending *pending = [info.pending lastObject];
    [info.pending removeLastObject];

    NSArray *array = NSKVOObjectValueForKey(self, key);
    id oldValue = nil;
    id newValue = nil;
    switch (change) {
        case NSKeyValueChangeInsertion:
            newValue = array != nil ? NSKVOSubarrayAtIndexes(array, indexes) : nil;
            break;
        case NSKeyValueChangeRemoval:
            oldValue = pending.oldValues;
            break;
        case NSKeyValueChangeReplacement:
            oldValue = pending.oldValues;
            newValue = array != nil ? NSKVOSubarrayAtIndexes(array, indexes) : nil;
            break;
        default:
            break;
    }
    NSKVONotifyKey(self, key, change, oldValue, newValue, indexes, NO);
}

- (void)willChangeValueForKey:(NSString *)key
               withSetMutation:(NSKeyValueSetMutationKind)mutation
                  usingObjects:(NSSet *)objects {
    _NSKVOInfo *info = NSKVOInfoForObject(self, NO);
    if (info == nil || !NSKVOHasObservers(self, key)) {
        return;
    }

    NSInteger change;
    switch (mutation) {
        case NSKeyValueUnionSetMutation: change = NSKeyValueChangeInsertion; break;
        case NSKeyValueMinusSetMutation: change = NSKeyValueChangeRemoval; break;
        case NSKeyValueIntersectSetMutation: change = NSKeyValueChangeRemoval; break;
        case NSKeyValueSetSetMutation: change = NSKeyValueChangeReplacement; break;
        default: change = NSKeyValueChangeSetting; break;
    }
    id oldValue = [self valueForKey:key];
    id priorOld = (change == NSKeyValueChangeInsertion) ? nil : oldValue;
    NSKVONotifyKey(self, key, change, priorOld, nil, nil, YES);

    _NSKVOPending *pending = [[_NSKVOPending alloc] init];
    pending.type = _NSKVOPendingSet;
    pending.kind = change;
    pending.targets = @[ key ];
    pending.objects = objects;
    pending.oldValue = oldValue;
    [info.pending addObject:pending];
}

- (void)didChangeValueForKey:(NSString *)key
              withSetMutation:(NSKeyValueSetMutationKind)mutation
                 usingObjects:(NSSet *)objects {
    _NSKVOInfo *info = NSKVOInfoForObject(self, NO);
    if (info == nil || [info.pending count] == 0) {
        return;
    }

    _NSKVOPending *pending = [info.pending lastObject];
    [info.pending removeLastObject];

    id oldValue = nil;
    id newValue = nil;
    switch (pending.kind) {
        case NSKeyValueChangeInsertion:
            newValue = objects;
            break;
        case NSKeyValueChangeRemoval:
            oldValue = objects;
            break;
        case NSKeyValueChangeReplacement:
            oldValue = pending.oldValue;
            newValue = objects;
            break;
        default:
            break;
    }
    NSKVONotifyKey(self, key, pending.kind, oldValue, newValue, nil, NO);
}

- (void)setObservationInfo:(void *)newInfo {
    if (newInfo == NULL) {
        objc_setAssociatedObject(self, &kNSKVOExternalInfoKey, nil, OBJC_ASSOCIATION_RETAIN);
    } else {
        objc_setAssociatedObject(self, &kNSKVOExternalInfoKey,
                                 [NSValue valueWithPointer:newInfo], OBJC_ASSOCIATION_RETAIN);
    }
}

- (void *)observationInfo {
    _NSKVOInfo *info = NSKVOInfoForObject(self, NO);
    if (info != nil && [info.registrations count] > 0) {
        return (__bridge void *)info;
    }
    NSValue *external = objc_getAssociatedObject(self, &kNSKVOExternalInfoKey);
    return external != nil ? [external pointerValue] : NULL;
}

@end

#pragma mark - Customization

@implementation NSObject (NSKeyValueObservingCustomization)

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    NSString *selectorName = [NSString stringWithFormat:@"automaticallyNotifiesObserversOf%@",
                                                       NSKVOCapitalizedKey(key)];
    SEL selector = NSSelectorFromString(selectorName);
    if ([self respondsToSelector:selector]) {
        IMP imp = [self methodForSelector:selector];
        return ((BOOL (*)(id, SEL, NSString *))imp)(self, selector, key);
    }
    return YES;
}

+ (NSSet *)keyPathsForValuesAffectingValueForKey:(NSString *)key {
    NSString *selectorName = [NSString stringWithFormat:@"keyPathsForValuesAffecting%@",
                                                       NSKVOCapitalizedKey(key)];
    SEL selector = NSSelectorFromString(selectorName);
    if ([self respondsToSelector:selector]) {
        IMP imp = [self methodForSelector:selector];
        return ((id (*)(id, SEL, NSString *))imp)(self, selector, key);
    }
    NSDictionary *forClass = [NSKVODependentRegistry() objectForKey:NSStringFromClass(self)];
    NSSet *registered = [forClass objectForKey:key];
    return registered != nil ? registered : [NSSet set];
}

+ (void)setKeys:(NSArray *)keys triggerChangeNotificationsForDependentKey:(NSString *)dependentKey {
    NSMutableDictionary *registry = NSKVODependentRegistry();
    NSString *className = NSStringFromClass(self);
    NSMutableDictionary *forClass = [registry objectForKey:className];
    if (forClass == nil) {
        forClass = [NSMutableDictionary dictionary];
        [registry setObject:forClass forKey:className];
    }
    [forClass setObject:[NSSet setWithArray:keys] forKey:dependentKey];
}

@end