/*
 * Copyright (C) 2026, LibreDarwin.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSZone.h>
#include <string.h>

static NSUInteger NSStringHashZeroTerminatedASCII(const char *string) {
    NSUInteger hash = 0;
    while (*string)
        hash = hash * 31 + (unsigned char)*string++;
    return hash;
}

@implementation NSMethodSignature

-initWithTypes:(const char *)typesCString {
   const char *next,*last;
   NSUInteger  size,align;
   BOOL        first=YES;
   size_t      typesCStringLength=strlen(typesCString);
   char       *types[typesCStringLength]; // at most strlen arguments
   
    // not guaranteed that typesCString is static
   _typesCString=NSZoneMalloc(NULL,typesCStringLength+1);
   strcpy(_typesCString,typesCString);
   next=last=_typesCString;
   _returnType=NULL;
   _numberOfArguments=0;

   while((next=NSGetSizeAndAlignment(next,&size,&align))!=last){
    NSUInteger length=next-last;
    char      *nextCString=NSZoneMalloc(NULL,length+1);
    
    strncpy(nextCString,last,length);
    nextCString[length]='\0';

    if(first)
     _returnType=nextCString;
    else {
     types[_numberOfArguments]=nextCString;
     _numberOfArguments++;
    }
    
    first=NO;

    while((*next>='0' && *next<='9') || *next=='+' || *next=='-' || *next=='?')
     next++; 

    if(*next=='\0')
      break;

    last=next;
   }
   
   if(_numberOfArguments){  
    _types=NSZoneMalloc(NULL,_numberOfArguments*sizeof(char *));
    
    NSInteger i;
    
    for(i=0;i<_numberOfArguments;i++)
     _types[i]=types[i];
   }
   
   return self;
}

-(void)dealloc {
   NSZoneFree(NULL,_typesCString);
   
   if(_returnType!=NULL)
    NSZoneFree(NULL,_returnType);
   
   NSInteger i;
   if(_types!=NULL){
    for(i=0;i<_numberOfArguments;i++)
     NSZoneFree(NULL,_types[i]);
    NSZoneFree(NULL,_types);
   }
   
   [super dealloc];
}

+(NSMethodSignature *)signatureWithObjCTypes:(const char *)typesCString {
   return [[[NSMethodSignature allocWithZone:NULL] initWithTypes:typesCString] autorelease];
}

-(NSString *)description {
   return [NSString stringWithFormat:@"<NSMethodSignature: -(%s)%s>",_returnType,_typesCString];
}

-(NSUInteger)hash {
   return NSStringHashZeroTerminatedASCII(_typesCString);
}

-(BOOL)isEqual:otherObject {
   if(self==otherObject)
    return YES;

   if([otherObject isKindOfClass:[NSMethodSignature class]]){
    NSMethodSignature *other=otherObject;

    return (strcmp(_typesCString,other->_typesCString)==0)?YES:NO;
   }

   return NO;
}

-(BOOL)isOneway {
   return (_returnType!=NULL && _returnType[0]=='V');
}

-(NSUInteger)frameLength {
   NSUInteger result=0;
   NSInteger  i;

   for(i=0;i<_numberOfArguments;i++){
    NSUInteger align;
    NSUInteger naturalSize;
    NSUInteger promotedSize;

    NSGetSizeAndAlignment(_types[i],&naturalSize,&align);
    promotedSize=((naturalSize+sizeof(long)-1)/sizeof(long))*sizeof(long);

    result+=promotedSize;
   }
   return result;
}

-(NSUInteger)methodReturnLength {
   NSUInteger size,align;

   NSGetSizeAndAlignment(_returnType,&size,&align);

   return size;
}

-(const char *)methodReturnType {
   return _returnType;
}

-(NSUInteger)numberOfArguments {
   return _numberOfArguments;
}

-(const char *)getArgumentTypeAtIndex:(NSUInteger)index {
   if(index>=_numberOfArguments){
    [NSException raise:NSInvalidArgumentException format:@"index (%lu) is beyond number of arguments (%lu)",(unsigned long)index,(unsigned long)_numberOfArguments];
    return NULL;
   }
   
   return _types[index];
}

@end
