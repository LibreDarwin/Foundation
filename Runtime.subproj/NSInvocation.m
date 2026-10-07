/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>

#include <string.h>
#include <objc/runtime.h>

/*
 * AArch64 register/stack call shim.  NSInvocation cannot use the
 * GNU-runtime objc_msgSendv (not present in Apple's libobjc), and
 * __builtin_apply/__builtin_apply_args are unavailable on arm64 clang.
 * So we marshal the arguments ourselves and make the call from a small
 * assembly trampoline.
 *
 *   void NSInvocationPerformCall(void *fn,
 *                                const uint64_t gp[8],   // x0..x7
 *                                const double   fp[8],   // d0..d7
 *                                const void    *stack,   // spilled args
 *                                size_t         stackSize,
 *                                void          *result); // [0]=x0 [8]=d0
 */
extern void NSInvocationPerformCall(void *fn, const uint64_t gp[8],
                                    const double fp[8], const void *stack,
                                    size_t stackSize, void *result);

__asm__(
".text\n"
".p2align 2\n"
".globl _NSInvocationPerformCall\n"
"_NSInvocationPerformCall:\n"
"    stp x29, x30, [sp, #-16]!\n"
"    mov x29, sp\n"
"    stp x19, x20, [sp, #-16]!\n"
"    stp x21, x22, [sp, #-16]!\n"
"    mov x19, x0\n"          // fn
"    mov x20, x5\n"          // result
"    mov x21, x1\n"          // gp array
"    mov x22, x2\n"          // fp array
"    add x9, x4, #15\n"      // round stack size up to 16
"    and x9, x9, #-16\n"
"    sub sp, sp, x9\n"
"    mov x10, sp\n"          // copy spilled args onto the stack
"0:  cbz x4, 1f\n"
"    ldrb w11, [x3], #1\n"
"    strb w11, [x10], #1\n"
"    subs x4, x4, #1\n"
"    b 0b\n"
"1:\n"
"    ldp d0, d1, [x22, #0]\n"
"    ldp d2, d3, [x22, #16]\n"
"    ldp d4, d5, [x22, #32]\n"
"    ldp d6, d7, [x22, #48]\n"
"    ldp x9,  x10, [x21, #0]\n"
"    ldp x11, x12, [x21, #16]\n"
"    ldp x13, x14, [x21, #32]\n"
"    ldp x15, x16, [x21, #48]\n"
"    mov x0, x9\n"
"    mov x1, x10\n"
"    mov x2, x11\n"
"    mov x3, x12\n"
"    mov x4, x13\n"
"    mov x5, x14\n"
"    mov x6, x15\n"
"    mov x7, x16\n"
"    blr x19\n"
"    str x0, [x20, #0]\n"    // integer / pointer return
"    str d0, [x20, #8]\n"    // floating point return
"    mov sp, x29\n"
"    sub sp, sp, #32\n"
"    ldp x21, x22, [sp], #16\n"
"    ldp x19, x20, [sp], #16\n"
"    ldp x29, x30, [sp], #16\n"
"    ret\n"
);

@implementation NSInvocation

-(void)buildFrame {
   NSInteger  i,count=[_signature numberOfArguments];
   NSUInteger align;

   NSGetSizeAndAlignment([_signature methodReturnType],&_returnSize,&align);
   _returnValue=NSZoneCalloc(NULL,MAX(_returnSize, sizeof(long)),1);

   _argumentFrameSize=0;
   _argumentSizes=NSZoneCalloc(NULL,count,sizeof(NSUInteger));
   _argumentOffsets=NSZoneCalloc(NULL,count,sizeof(NSUInteger));

   for(i=0;i<count;i++){
    NSUInteger naturalSize;
    NSUInteger promotedSize;

    _argumentOffsets[i]=_argumentFrameSize;

    NSGetSizeAndAlignment([_signature getArgumentTypeAtIndex:i],&naturalSize,&align);
    promotedSize=((naturalSize+sizeof(long)-1)/sizeof(long))*sizeof(long);

    _argumentSizes[i]=naturalSize;
    _argumentFrameSize+=promotedSize;
   }
}

-initWithMethodSignature:(NSMethodSignature *)signature {
   if(signature==nil){
    [NSException raise:NSInvalidArgumentException format:@"nil signature in NSInvocation creation"];
    return nil;
   }

   _signature=[signature retain];

   [self buildFrame];

   _argumentFrame=NSZoneCalloc(NULL,_argumentFrameSize,1);

   return self;
}

-initWithMethodSignature:(NSMethodSignature *)signature arguments:(void *)arguments {
   unsigned       i;
   uint8_t *stackFrame=arguments;

   [self initWithMethodSignature:signature];

   for(i=0;i<_argumentFrameSize;i++)
    _argumentFrame[i]=stackFrame[i];

   return self;
}

-(void)dealloc {
    if (_retainArguments) {
        NSInteger i, count = [_signature numberOfArguments];

        for (i = 0; i < count; ++i) {
            const char *type = [_signature getArgumentTypeAtIndex:i];

            switch (type[0]) {
                case '@': {
                    id object;

                    [self getArgument:&object atIndex:i];
                    [object release];
                    break;
                }

                case '*': {
                    char *ptr;

                    [self getArgument:&ptr atIndex:i];
                    NSZoneFree(NULL, ptr);
                    break;
                }

                default:
                    break;
            }
        }
    }

   NSZoneFree(NULL,_returnValue);
   NSZoneFree(NULL,_argumentSizes);
   NSZoneFree(NULL,_argumentOffsets);
   NSZoneFree(NULL,_argumentFrame);
   [_signature release];
   [super dealloc];
}

static void *bufferForType(void *buffer,const char *type){
   NSUInteger size,align;

   NSGetSizeAndAlignment(type,&size,&align);
   if(buffer!=NULL)
    NSZoneFree(NULL,buffer);

   return NSZoneMalloc(NULL,size);
}

-initWithCoder:(NSCoder *)coder {
   const char *type;
   NSInteger         i,count;
   void       *buffer=NULL;

   _signature=[[coder decodeObject] retain];

   [self buildFrame];

   _argumentFrame=NSZoneCalloc(NULL,_argumentFrameSize,1);

   if([_signature methodReturnLength]>0){
    type=[_signature methodReturnType];
    buffer=bufferForType(buffer,type);
    [coder decodeValueOfObjCType:type at:buffer];
    [self setReturnValue:buffer];
   }

   count=[_signature numberOfArguments];
   for(i=0;i<count;i++){
    type=[_signature getArgumentTypeAtIndex:i];
    buffer=bufferForType(buffer,type);
    [coder decodeValueOfObjCType:type at:buffer];
    [self setArgument:buffer atIndex:i];
   }
   NSZoneFree(NULL,buffer);

   return self;
}

-(void)encodeWithCoder:(NSCoder *)coder {
   const char *type;
   NSInteger         i,count;
   void       *buffer=NULL;

   [coder encodeObject:_signature];

   if([_signature methodReturnLength]>0){
    type=[_signature methodReturnType];
    buffer=bufferForType(buffer,type);
    [self getReturnValue:buffer];
    [coder encodeValueOfObjCType:type at:buffer];
   }

   count=[_signature numberOfArguments];
   for(i=0;i<count;i++){
    type=[_signature getArgumentTypeAtIndex:i];
    buffer=bufferForType(buffer,type);
    [self getArgument:buffer atIndex:i];
    [coder encodeValueOfObjCType:type at:buffer];
   }
}

+(NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature {
   return [[[self allocWithZone:NULL] initWithMethodSignature:signature] autorelease];
}

+(NSInvocation *)invocationWithMethodSignature:(NSMethodSignature *)signature arguments:(void *)arguments {
   return [[[self allocWithZone:NULL] initWithMethodSignature:signature arguments:arguments] autorelease];
}

-(NSMethodSignature *)methodSignature {
   return _signature;
}

static void byteCopy(void *src,void *dst,NSUInteger length){
   NSInteger i;

   for(i=0;i<length;i++)
    ((char *)dst)[i]=((char *)src)[i];
}

-(void)getReturnValue:(void *)pointerToValue {
   byteCopy(_returnValue,pointerToValue,_returnSize);
}

-(void)setReturnValue:(void *)pointerToValue {
   byteCopy(pointerToValue,_returnValue,_returnSize);
}


-(void)getArgument:(void *)pointerToValue atIndex:(NSInteger)index
{
    NSUInteger naturalSize = _argumentSizes[index];
    byteCopy(_argumentFrame + _argumentOffsets[index], pointerToValue, naturalSize);
}

-(void)setArgument:(void *)pointerToValue atIndex:(NSInteger)index
{
    NSUInteger naturalSize = _argumentSizes[index];
    byteCopy(pointerToValue, _argumentFrame + _argumentOffsets[index], naturalSize);
}

-(void)retainArguments {
   if(_retainArguments)
    return;

   _retainArguments=YES;

   NSInteger i,count=[_signature numberOfArguments];

   for(i=0;i<count;i++){
    const char *type=[_signature getArgumentTypeAtIndex:i];

    switch(type[0]){
     case '@': {
      id object;

      [self getArgument:&object atIndex:i];
      [object retain];
      break;
     }

     case '*': {
      char *ptr;
      char *copy;

      [self getArgument:&ptr atIndex:i];
      copy=NSZoneMalloc(NULL,strlen(ptr)+1);
      strcpy(copy,ptr);
      [self setArgument:&copy atIndex:i];
      break;
     }

     default:
      break;
    }
   }
}

-(BOOL)argumentsRetained {
   return _retainArguments;
}

-(SEL)selector {
   SEL selector;

   [self getArgument:&selector atIndex:1];
   return selector;
}

-(void)setSelector:(SEL)selector {
   [self setArgument:&selector atIndex:1];
}

-target {
   id target;

   [self getArgument:&target atIndex:0];
   return target;
}

-(void)setTarget:target {
   [self setArgument:&target atIndex:0];
}

static const char *skipQualifiers(const char *type) {
   while(*type=='r' || *type=='n' || *type=='N' || *type=='o' ||
         *type=='O' || *type=='R' || *type=='V')
    type++;
   return type;
}

-(void)invoke {
   id target=[self target];
   SEL selector;

   [self getArgument:&selector atIndex:1];

   if(target==nil){
    if(_returnValue!=NULL)
     memset(_returnValue,0,_returnSize);
    return;
   }

   const char *returnType=skipQualifiers([_signature methodReturnType]);
   const char *argType;

   if(returnType[0]=='{' || returnType[0]=='(' || returnType[0]=='[')
    [NSException raise:NSInvalidArgumentException
                format:@"NSInvocation: struct/union/array return values are not supported"];

   uint64_t gp[8]={0,0,0,0,0,0,0,0};
   double   fp[8]={0,0,0,0,0,0,0,0};
   NSInteger count=[_signature numberOfArguments];
   NSInteger i;
   int gpCount=0, fpCount=0;
   BOOL spilledGp=NO, spilledFp=NO;
   uint8_t *stack=NSZoneMalloc(NULL,(_argumentFrameSize>0)?_argumentFrameSize:1);
   NSUInteger stackSize=0;

   for(i=0;i<count;i++){
    argType=skipQualifiers([_signature getArgumentTypeAtIndex:i]);

    if(argType[0]=='{' || argType[0]=='(' || argType[0]=='['){
     NSZoneFree(NULL,stack);
     [NSException raise:NSInvalidArgumentException
                 format:@"NSInvocation: struct/union/array arguments are not supported"];
    }

    NSUInteger size=_argumentSizes[i];
    if(size>sizeof(uint64_t))
     size=sizeof(uint64_t);

    void *src=_argumentFrame+_argumentOffsets[i];

    if(argType[0]=='f' || argType[0]=='d'){
     if(fpCount<8 && !spilledFp){
      memcpy(&fp[fpCount],src,size);
      fpCount++;
     } else {
      spilledFp=YES;
      memcpy(stack+stackSize,src,size);
      stackSize+=8;
     }
    } else {
     if(gpCount<8 && !spilledGp){
      memcpy(&gp[gpCount],src,size);
      gpCount++;
     } else {
      spilledGp=YES;
      memcpy(stack+stackSize,src,size);
      stackSize+=8;
     }
    }
   }

   IMP fn=[target methodForSelector:selector];
   uint64_t result[2]={0,0};

   NSInvocationPerformCall((void *)fn,gp,fp,stack,stackSize,result);

   NSZoneFree(NULL,stack);

   if(returnType[0]=='f' || returnType[0]=='d')
    byteCopy((uint8_t *)result+8,_returnValue,_returnSize);
   else
    byteCopy(result,_returnValue,_returnSize);
}

-(void)invokeWithTarget:target {
   [self setTarget:target];
   [self invoke];
}

-(id)description
{
   return [NSString stringWithFormat:@"<%@ with signature %@>", [super description], [_signature description]];
}

@end

@implementation NSObject (NSForwarding)

-(NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
   Method method=class_getInstanceMethod(object_getClass(self),selector);

   if(method==NULL)
    return nil;

   return [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
}

+(NSMethodSignature *)instanceMethodSignatureForSelector:(SEL)selector {
   Method method=class_getInstanceMethod(self,selector);

   if(method==NULL)
    return nil;

   return [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
}

-(void)forwardInvocation:(NSInvocation *)invocation {
   [NSException raise:NSInvalidArgumentException
               format:@"*** -[%@ %@]: selector not recognized",
                      NSStringFromClass(object_getClass(self)),
                      NSStringFromSelector([invocation selector])];
}

-(id)forwardingTargetForSelector:(SEL)selector {
   return nil;
}

@end