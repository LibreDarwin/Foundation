/*
#import <Foundation/NSNumber.h>
	NSFileWrapper.m
	Copyright (c) 1995-2019, Apple Inc.
	Portions Copyright (c) 2006-2015 Apple Inc. All rights reserved.
*/

#import <Foundation/NSFileWrapper.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSError.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSException.h>

@implementation NSFileWrapper {
    id _contents;
    NSString *_preferredFilename;
    NSString *_filename;
    NSDictionary *_fileAttributes;
    BOOL _isDirectory;
    BOOL _isRegularFile;
    BOOL _isSymbolicLink;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

#pragma mark - Initializers

- (instancetype)init
{
    return [self initDirectoryWithFileWrappers:nil];
}

- (instancetype)initWithURL:(NSURL *)url options:(NSFileWrapperReadingOptions)options error:(NSError **)outError
{
    if (outError) *outError = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:outError];
    if (data == nil) {
        return nil;
    }
    return [self initRegularFileWithContents:data];
}

- (instancetype)initDirectoryWithFileWrappers:(NSDictionary<NSString *, NSFileWrapper *> *)childrenByPreferredName
{
    self = [super init];
    if (self) {
        _isDirectory = YES;
        _isRegularFile = NO;
        _isSymbolicLink = NO;
        _contents = [[NSMutableDictionary alloc] initWithDictionary:childrenByPreferredName ?: @{}];
        _preferredFilename = nil;
        _filename = nil;
        _fileAttributes = [[NSDictionary alloc] init];
    }
    return self;
}

- (instancetype)initRegularFileWithContents:(NSData *)contents
{
    self = [super init];
    if (self) {
        _isDirectory = NO;
        _isRegularFile = YES;
        _isSymbolicLink = NO;
        _contents = [contents copy];
        _preferredFilename = nil;
        _filename = nil;
        _fileAttributes = [[NSDictionary alloc] init];
    }
    return self;
}

- (instancetype)initSymbolicLinkWithDestinationURL:(NSURL *)url
{
    self = [super init];
    if (self) {
        _isDirectory = NO;
        _isRegularFile = NO;
        _isSymbolicLink = YES;
        _contents = [url copy];
        _preferredFilename = nil;
        _filename = nil;
        _fileAttributes = [[NSDictionary alloc] init];
    }
    return self;
}

- (instancetype)initWithSerializedRepresentation:(NSData *)serializeRepresentation
{
    if (serializeRepresentation == nil || serializeRepresentation.length == 0) {
        return [self initRegularFileWithContents:[NSData data]];
    }
    // Minimal: treat as regular file contents for now; full format decoding TBD
    return [self initRegularFileWithContents:[serializeRepresentation copy]];
}

- (instancetype)initWithCoder:(NSCoder *)inCoder
{
    // Basic secure coding support
    if ([inCoder allowsKeyedCoding]) {
        NSString *type = [inCoder decodeObjectOfClass:[NSString class] forKey:@"NSFileWrapperType"];
        if ([type isEqualToString:@"NSFileWrapperDirectory"]) {
            NSDictionary *children = [inCoder decodeObjectOfClass:[NSDictionary class] forKey:@"NSFileWrapperChildren"];
            self = [self initDirectoryWithFileWrappers:children];
        } else if ([type isEqualToString:@"NSFileWrapperRegularFile"]) {
            NSData *data = [inCoder decodeObjectOfClass:[NSData class] forKey:@"NSFileWrapperContents"];
            self = [self initRegularFileWithContents:data ?: [NSData data]];
        } else if ([type isEqualToString:@"NSFileWrapperSymbolicLink"]) {
            NSURL *dest = [inCoder decodeObjectOfClass:[NSURL class] forKey:@"NSFileWrapperDestinationURL"];
            self = [self initSymbolicLinkWithDestinationURL:dest ?: [NSURL URLWithString:@""]];
        } else {
            self = [self initRegularFileWithContents:[NSData data]];
        }
        _preferredFilename = [[inCoder decodeObjectOfClass:[NSString class] forKey:@"NSFileWrapperPreferredFilename"] copy];
        _filename = [[inCoder decodeObjectOfClass:[NSString class] forKey:@"NSFileWrapperFilename"] copy];
        _fileAttributes = [[inCoder decodeObjectOfClass:[NSDictionary class] forKey:@"NSFileWrapperFileAttributes"] copy] ?: [[NSDictionary alloc] init];
        return self;
    }
    return [self initRegularFileWithContents:[NSData data]];
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    if (![coder allowsKeyedCoding]) return;
    if (_isDirectory) {
        [coder encodeObject:@"NSFileWrapperDirectory" forKey:@"NSFileWrapperType"];
        [coder encodeObject:_contents forKey:@"NSFileWrapperChildren"];
    } else if (_isRegularFile) {
        [coder encodeObject:@"NSFileWrapperRegularFile" forKey:@"NSFileWrapperType"];
        [coder encodeObject:_contents forKey:@"NSFileWrapperContents"];
    } else if (_isSymbolicLink) {
        [coder encodeObject:@"NSFileWrapperSymbolicLink" forKey:@"NSFileWrapperType"];
        [coder encodeObject:_contents forKey:@"NSFileWrapperDestinationURL"];
    }
    [coder encodeObject:_preferredFilename forKey:@"NSFileWrapperPreferredFilename"];
    [coder encodeObject:_filename forKey:@"NSFileWrapperFilename"];
    [coder encodeObject:_fileAttributes forKey:@"NSFileWrapperFileAttributes"];
}

- (void)dealloc
{
    [_contents release];
    [_preferredFilename release];
    [_filename release];
    [_fileAttributes release];
    [super dealloc];
}

#pragma mark - Properties

- (BOOL)isDirectory { return _isDirectory; }
- (BOOL)isRegularFile { return _isRegularFile; }
- (BOOL)isSymbolicLink { return _isSymbolicLink; }

- (NSString *)preferredFilename { return _preferredFilename; }
- (void)setPreferredFilename:(NSString *)preferredFilename
{
    if (_preferredFilename == preferredFilename) return;
    [_preferredFilename release];
    _preferredFilename = [preferredFilename copy];
}

- (NSString *)filename { return _filename; }
- (void)setFilename:(NSString *)filename
{
    if (_filename == filename) return;
    [_filename release];
    _filename = [filename copy];
}

- (NSDictionary *)fileAttributes { return _fileAttributes; }
- (void)setFileAttributes:(NSDictionary *)fileAttributes
{
    if (_fileAttributes == fileAttributes) return;
    [_fileAttributes release];
    _fileAttributes = [fileAttributes copy];
}

#pragma mark - Reading/Writing

- (BOOL)matchesContentsOfURL:(NSURL *)url
{
    return NO;
}

- (BOOL)readFromURL:(NSURL *)url options:(NSFileWrapperReadingOptions)options error:(NSError **)outError
{
    id old = self;
    NSFileWrapper *replacement = [[NSFileWrapper alloc] initWithURL:url options:options error:outError];
    if (replacement == nil) return NO;
    // Copy state
    [_contents release];
    [_preferredFilename release];
    [_filename release];
    [_fileAttributes release];
    _contents = [replacement->_contents retain];
    _preferredFilename = [replacement->_preferredFilename copy];
    _filename = [replacement->_filename copy];
    _fileAttributes = [replacement->_fileAttributes copy];
    _isDirectory = replacement->_isDirectory;
    _isRegularFile = replacement->_isRegularFile;
    _isSymbolicLink = replacement->_isSymbolicLink;
    [replacement release];
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url options:(NSFileWrapperWritingOptions)options originalContentsURL:(NSURL *)originalContentsURL error:(NSError **)outError
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (_isRegularFile) {
        return [(NSData *)_contents writeToURL:url options:(options & NSFileWrapperWritingAtomic) ? 0 : 0 error:outError];
    } else if (_isSymbolicLink) {
        return [fm createSymbolicLinkAtURL:url withDestinationURL:(NSURL *)_contents error:outError];
    } else if (_isDirectory) {
        if (![fm createDirectoryAtURL:url withIntermediateDirectories:YES attributes:_fileAttributes error:outError]) {
            return NO;
        }
        NSDictionary *children = (NSDictionary *)_contents;
        for (NSString *name in children) {
            NSFileWrapper *child = children[name];
            NSString *useName = child.filename ?: child.preferredFilename ?: name;
            NSURL *childURL = [url URLByAppendingPathComponent:useName];
            if (![child writeToURL:childURL options:options originalContentsURL:nil error:outError]) {
                return NO;
            }
        }
        return YES;
    }
    return NO;
}

#pragma mark - Serialization

- (NSData *)serializedRepresentation
{
    // Return a basic representation; full format to be implemented to match Apple
    if (_isRegularFile) {
        return [[_contents copy] autorelease];
    } else if (_isDirectory) {
        // For now, return empty data as a minimal stub
        return [NSData data];
    } else if (_isSymbolicLink) {
        return [[_contents absoluteString] dataUsingEncoding:NSUTF8StringEncoding];
    }
    return [NSData data];
}

#pragma mark - Directories

- (NSString *)addFileWrapper:(NSFileWrapper *)child
{
    if (!_isDirectory) {
        [NSException raise:NSInvalidArgumentException format:@"addFileWrapper: called on non-directory wrapper"];
        return nil;
    }
    NSMutableDictionary *dict = (NSMutableDictionary *)_contents;
    NSString *name = child.preferredFilename ?: child.filename ?: [NSString stringWithFormat:@"file-%lu", (unsigned long)[dict count]];
    // Ensure unique
    if ([dict objectForKey:name]) {
        NSUInteger i = 2;
        while ([dict objectForKey:[NSString stringWithFormat:@"%@-%lu", name, (unsigned long)i]]) i++;
        name = [NSString stringWithFormat:@"%@-%lu", name, (unsigned long)i];
    }
    [dict setObject:child forKey:name];
    return name;
}

- (NSString *)addRegularFileWithContents:(NSData *)data preferredFilename:(NSString *)fileName
{
    NSFileWrapper *fw = [[[NSFileWrapper alloc] initRegularFileWithContents:data] autorelease];
    fw.preferredFilename = fileName;
    return [self addFileWrapper:fw];
}

- (void)removeFileWrapper:(NSFileWrapper *)child
{
    if (!_isDirectory) {
        [NSException raise:NSInvalidArgumentException format:@"removeFileWrapper: called on non-directory wrapper"];
        return;
    }
    NSMutableDictionary *dict = (NSMutableDictionary *)_contents;
    NSString *key = [self keyForFileWrapper:child];
    if (key) {
        [dict removeObjectForKey:key];
    }
}

- (NSDictionary *)fileWrappers
{
    if (!_isDirectory) {
        [NSException raise:NSInvalidArgumentException format:@"fileWrappers called on non-directory wrapper"];
        return nil;
    }
    return [[_contents retain] autorelease];
}

- (NSString *)keyForFileWrapper:(NSFileWrapper *)child
{
    if (!_isDirectory) return nil;
    NSDictionary *dict = (NSDictionary *)_contents;
    for (NSString *key in dict) {
        if (dict[key] == child) return key;
    }
    return nil;
}

#pragma mark - Regular Files

- (NSData *)regularFileContents
{
    if (!_isRegularFile) {
        [NSException raise:NSInvalidArgumentException format:@"regularFileContents called on non-regular-file wrapper"];
        return nil;
    }
    return [[_contents retain] autorelease];
}

#pragma mark - Symbolic Links

- (NSURL *)symbolicLinkDestinationURL
{
    if (!_isSymbolicLink) {
        [NSException raise:NSInvalidArgumentException format:@"symbolicLinkDestinationURL called on non-symbolic-link wrapper"];
        return nil;
    }
    return [[_contents retain] autorelease];
}

@end

#if TARGET_OS_OSX
@implementation NSFileWrapper(NSDeprecated)
- (id)initWithPath:(NSString *)path { return [self initWithURL:[NSURL fileURLWithPath:path] options:0 error:NULL]; }
- (id)initSymbolicLinkWithDestination:(NSString *)path { return [self initSymbolicLinkWithDestinationURL:[NSURL fileURLWithPath:path]]; }
- (BOOL)needsToBeUpdatedFromPath:(NSString *)path { return [self matchesContentsOfURL:[NSURL fileURLWithPath:path]]; }
- (BOOL)updateFromPath:(NSString *)path { return [self readFromURL:[NSURL fileURLWithPath:path] options:0 error:NULL]; }
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)atomicFlag updateFilenames:(BOOL)updateFilenamesFlag { return [self writeToURL:[NSURL fileURLWithPath:path] options:atomicFlag?NSFileWrapperWritingAtomic:0 originalContentsURL:nil error:NULL]; }
- (NSString *)addFileWithPath:(NSString *)path { return [self addRegularFileWithContents:[NSData dataWithContentsOfFile:path] preferredFilename:[path lastPathComponent]]; }
- (NSString *)addSymbolicLinkWithDestination:(NSString *)path preferredFilename:(NSString *)filename { NSFileWrapper *fw=[[[NSFileWrapper alloc]initSymbolicLinkWithDestination:path]autorelease]; fw.preferredFilename=filename; return [self addFileWrapper:fw]; }
- (NSString *)symbolicLinkDestination { return [(NSURL*)_contents path]; }
@end
#endif

/* Internal classes inferred from disasm */
@interface NSDocInfo : NSObject <NSCopying> {
@public
    unsigned long long _modTime; /* offset ~8 */
    unsigned short _mode;        /* offset ~16 */
    unsigned short _flags;       /* offset ~18 */
}
@end

@implementation NSDocInfo
- (id)copyWithZone:(NSZone *)zone
{
    NSDocInfo *c = [[[NSDocInfo allocWithZone:zone] init] autorelease];
    if (c) {
        c->_modTime = _modTime;
        c->_mode = _mode;
        c->_flags = _flags;
    }
    return c;
}
@end

/* Simple AK serializer/deserializer minimal stubs - expand as needed */
@interface NSAKSerializerStream : NSObject {
    NSMutableData *_data;
}
- (NSMutableData *)mutableData;
@end

@implementation NSAKSerializerStream
- (instancetype)init
{
    self = [super init];
    if (self) {
        _data = [[NSMutableData alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [_data release];
    [super dealloc];
}
- (NSMutableData *)mutableData { return _data; }
- (id)writeInt:(int)value
{
    unsigned int v = (unsigned int)value;
    [_data appendBytes:&v length:4];
    return self;
}
- (id)writeAlignedDataSize:(unsigned long long)size
{
    // simple 4-byte for now
    unsigned int v = (unsigned int)size;
    [_data appendBytes:&v length:4];
    return self;
}
- (id)writeData:(const void *)bytes length:(NSUInteger)len
{
    if (bytes && len) [_data appendBytes:bytes length:len];
    return self;
}
- (id)writeDelayedInt:(int)value for:(int)offset { return self; }
@end

@interface NSAKSerializer : NSObject {
    NSAKSerializerStream *_stream;
}
- (instancetype)initForSerializerStream:(NSAKSerializerStream *)stream;
- (NSAKSerializerStream *)serializerStream;
- (unsigned long long)serializeObject:(id)obj;
@end

@implementation NSAKSerializer
- (instancetype)initForSerializerStream:(NSAKSerializerStream *)stream
{
    self = [super init];
    if (self) {
        _stream = [stream retain];
    }
    return self;
}
- (void)dealloc
{
    [_stream release];
    [super dealloc];
}
- (NSAKSerializerStream *)serializerStream { return _stream; }
- (unsigned long long)serializeObject:(id)obj
{
    if ([obj isKindOfClass:[NSData class]]) {
        id pos = [_stream writeInt:1];
        unsigned long long start = [_stream mutableData].length;
        unsigned long long sz = [obj length];
        [_stream writeAlignedDataSize:sz];
        [_stream writeData:[obj bytes] length:sz];
        return [_stream mutableData].length - start;
    } else if ([obj isKindOfClass:[NSArray class]]) {
        id pos = [_stream writeInt:2];
        unsigned long long start = [_stream mutableData].length;
        NSArray *a = obj;
        // write count
        [_stream writeInt:(int)[a count]];
        for (id x in a) {
            [self serializeObject:x];
        }
        return [_stream mutableData].length - start;
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        id pos = [_stream writeInt:3];
        unsigned long long start = [_stream mutableData].length;
        NSDictionary *d = obj;
        [_stream writeInt:(int)[d count]];
        for (id k in d) {
            [self serializeObject:k];
            [self serializeObject:d[k]];
        }
        return [_stream mutableData].length - start;
    } else if ([obj isKindOfClass:[NSString class]]) {
        id pos = [_stream writeInt:4];
        unsigned long long start = [_stream mutableData].length;
        NSData *sdata = [(NSString *)obj dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
        [_stream writeAlignedDataSize:sdata.length];
        [_stream writeData:sdata.bytes length:sdata.length];
        return [_stream mutableData].length - start;
    }
    // fallback: serialize as empty data
    [_stream writeInt:1];
    [_stream writeAlignedDataSize:0];
    return 0;
}
@end
