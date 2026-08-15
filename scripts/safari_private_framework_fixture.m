#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <unistd.h>

static NSString *const FixtureTitle = @"macos-data private Framework fixture";

static id SendObject(id target, NSString *selector) {
    id (*send)(id, SEL) = (void *)objc_msgSend;
    return send(target, NSSelectorFromString(selector));
}

static BOOL LoadOne(NSArray<NSString *> *paths) {
    for (NSString *path in paths) {
        if (dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) return YES;
    }
    return NO;
}

static BOOL LoadFrameworks(void) {
    return LoadOne(@[
        @"/System/Library/StagedFrameworks/Safari.framework/Versions/A/Safari",
        @"/System/Volumes/Preboot/Cryptexes/OS/System/Library/PrivateFrameworks/Safari.framework/Versions/A/Safari",
        @"/System/Library/PrivateFrameworks/Safari.framework/Versions/A/Safari"
    ]) && LoadOne(@[
        @"/System/Library/StagedFrameworks/SafariCore.framework/Versions/A/SafariCore",
        @"/System/Volumes/Preboot/Cryptexes/OS/System/Library/PrivateFrameworks/SafariCore.framework/Versions/A/SafariCore",
        @"/System/Library/PrivateFrameworks/SafariCore.framework/Versions/A/SafariCore"
    ]);
}

static BOOL HasClassMethod(Class cls, NSString *name) {
    return cls && class_getClassMethod(cls, NSSelectorFromString(name));
}

static BOOL HasInstanceMethod(Class cls, NSString *name) {
    return cls && class_getInstanceMethod(cls, NSSelectorFromString(name));
}

static BOOL IsSafeRegularOwnedFile(NSString *path) {
    struct stat value = {0};
    return lstat(path.fileSystemRepresentation, &value) == 0 &&
        (value.st_mode & S_IFMT) == S_IFREG && value.st_uid == geteuid();
}

static NSDictionary *LoadContext(NSString *path, NSString **error) {
    Class controllerClass = NSClassFromString(@"BookmarksController");
    Class groupClass = NSClassFromString(@"WebBookmarkGroup");
    Class leafClass = NSClassFromString(@"WebBookmarkLeaf");
    Class undoClass = NSClassFromString(@"BookmarksUndoController");
    BOOL methods =
        HasInstanceMethod(controllerClass, @"_initWithBookmarksFilePath:builtInBookmarksURL:migratedBookmarksFolder:siteMetadataManagerProvider:") &&
        HasInstanceMethod(controllerClass, @"allBookmarks") &&
        HasInstanceMethod(controllerClass, @"bookmarksBarCollection") &&
        HasClassMethod(controllerClass, @"requestSyncClientTriggerSyncForBookmarkGroup:") &&
        HasInstanceMethod(groupClass, @"load") &&
        HasInstanceMethod(groupClass, @"save") &&
        HasInstanceMethod(groupClass, @"bookmarkForUUID:") &&
        HasClassMethod(leafClass, @"bookmarkWithURLString:title:") &&
        HasInstanceMethod(undoClass, @"initWithUndoManager:dataStore:bookmarksController:") &&
        HasInstanceMethod(undoClass, @"insertBookmark:atIndex:inBookmarkFolder:allowDuplicateURLs:") &&
        HasInstanceMethod(undoClass, @"removeBookmarks:");
    if (!methods) {
        *error = @"private_method_drift";
        return nil;
    }

    id (*scopedInit)(id, SEL, id, id, id, id) = (void *)objc_msgSend;
    id controller = scopedInit([controllerClass alloc],
        NSSelectorFromString(@"_initWithBookmarksFilePath:builtInBookmarksURL:migratedBookmarksFolder:siteMetadataManagerProvider:"),
        path, nil, nil, nil);
    id group = controller ? SendObject(controller, @"allBookmarks") : nil;
    int (*sendInt)(id, SEL) = (void *)objc_msgSend;
    int loadResult = group ? sendInt(group, NSSelectorFromString(@"load")) : -1;
    id bar = nil;
    NSArray *children = nil;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while ([deadline timeIntervalSinceNow] > 0) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
        bar = SendObject(controller, @"bookmarksBarCollection");
        if (bar && [bar respondsToSelector:NSSelectorFromString(@"folderAndLeafChildren")]) {
            children = SendObject(bar, @"folderAndLeafChildren");
        }
        if (bar && children) break;
    }
    if (!controller || !group || !bar || !children || loadResult < 0) {
        *error = @"private_load_failed";
        return nil;
    }

    id (*undoInit)(id, SEL, id, id, id) = (void *)objc_msgSend;
    id undo = undoInit([undoClass alloc],
        NSSelectorFromString(@"initWithUndoManager:dataStore:bookmarksController:"),
        nil, controller, controller);
    if (!undo) {
        *error = @"private_undo_controller_failed";
        return nil;
    }
    return @{
        @"controller": controller,
        @"group": group,
        @"bar": bar,
        @"undo": undo,
        @"childCount": @(children.count)
    };
}

static void FindFixtureNodes(id node, NSString *url, NSMutableArray<NSDictionary *> *matches) {
    if (![node isKindOfClass:NSDictionary.class]) return;
    NSDictionary *dictionary = node;
    if ([dictionary[@"URLString"] isEqual:url]) [matches addObject:dictionary];
    id children = dictionary[@"Children"];
    if ([children isKindOfClass:NSArray.class]) {
        for (id child in children) FindFixtureNodes(child, url, matches);
    }
}

static NSDictionary *InspectPlist(NSString *path, NSString *url, NSString **error) {
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) {
        *error = @"plist_read_failed";
        return nil;
    }
    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    id root = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:&format error:nil];
    if (![root isKindOfClass:NSDictionary.class]) {
        *error = @"plist_parse_failed";
        return nil;
    }
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    FindFixtureNodes(root, url, matches);
    NSMutableSet<NSString *> *uuids = [NSMutableSet set];
    for (NSDictionary *node in matches) {
        if ([node[@"WebBookmarkUUID"] isKindOfClass:NSString.class]) [uuids addObject:node[@"WebBookmarkUUID"]];
    }
    NSArray *changes = [root[@"Sync"][@"Changes"] isKindOfClass:NSArray.class] ? root[@"Sync"][@"Changes"] : @[];
    NSUInteger addCount = 0;
    NSUInteger deleteCount = 0;
    for (NSDictionary *change in changes) {
        if (![change isKindOfClass:NSDictionary.class] || ![uuids containsObject:change[@"BookmarkUUID"]]) continue;
        if ([change[@"Type"] isEqual:@"Add"]) addCount++;
        if ([change[@"Type"] isEqual:@"Delete"]) deleteCount++;
    }
    return @{
        @"fixtureCount": @(matches.count),
        @"fixtureUUIDs": uuids.allObjects,
        @"syncChangeCount": @(changes.count),
        @"matchingAddCount": @(addCount),
        @"matchingDeleteCount": @(deleteCount)
    };
}

static BOOL WriteReceipt(NSString *path, NSDictionary *receipt, NSString **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:receipt options:NSJSONWritingSortedKeys error:nil];
    if (!data) {
        *error = @"receipt_encode_failed";
        return NO;
    }
    NSString *temporary = [path stringByAppendingFormat:@".%@.tmp", NSUUID.UUID.UUIDString.lowercaseString];
    int descriptor = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (descriptor < 0) {
        *error = @"receipt_create_failed";
        return NO;
    }
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;
    BOOL ok = YES;
    while (remaining > 0) {
        ssize_t count = write(descriptor, bytes, remaining);
        if (count <= 0) { ok = NO; break; }
        bytes += count;
        remaining -= (NSUInteger)count;
    }
    if (ok) ok = fsync(descriptor) == 0;
    close(descriptor);
    if (ok) ok = rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) == 0;
    if (!ok) {
        unlink(temporary.fileSystemRepresentation);
        *error = @"receipt_write_failed";
    }
    return ok;
}

static id CreateFixture(NSDictionary *context, NSString *url, NSString **error) {
    Class leafClass = NSClassFromString(@"WebBookmarkLeaf");
    id (*createLeaf)(id, SEL, id, id) = (void *)objc_msgSend;
    id leaf = createLeaf(leafClass, NSSelectorFromString(@"bookmarkWithURLString:title:"), url, FixtureTitle);
    if (!leaf) {
        *error = @"fixture_create_failed";
        return nil;
    }
    BOOL (*insert)(id, SEL, id, unsigned long long, id, BOOL) = (void *)objc_msgSend;
    BOOL inserted = insert(context[@"undo"],
        NSSelectorFromString(@"insertBookmark:atIndex:inBookmarkFolder:allowDuplicateURLs:"),
        leaf, [context[@"childCount"] unsignedLongLongValue], context[@"bar"], YES);
    if (!inserted) {
        *error = @"fixture_insert_failed";
        return nil;
    }
    return leaf;
}

static BOOL RemoveFixture(NSDictionary *context, id leaf, NSString **error) {
    (void)error;
    // The private method's return ABI has changed across Safari releases.
    // Treat it as void and prove the outcome with the post-save plist read-back.
    void (*remove)(id, SEL, id) = (void *)objc_msgSend;
    remove(context[@"undo"], NSSelectorFromString(@"removeBookmarks:"), @[leaf]);
    return YES;
}

static int SaveGroup(NSDictionary *context) {
    int (*save)(id, SEL) = (void *)objc_msgSend;
    return save(context[@"group"], NSSelectorFromString(@"save"));
}

static void RequestSync(NSDictionary *context) {
    void (*request)(id, SEL, id) = (void *)objc_msgSend;
    request(NSClassFromString(@"BookmarksController"),
        NSSelectorFromString(@"requestSyncClientTriggerSyncForBookmarkGroup:"), context[@"group"]);
}

static int CopyRoundTrip(NSString *path) {
    NSString *error = nil;
    NSDictionary *context = LoadContext(path, &error);
    if (!context) return 10;
    NSString *url = [@"https://example.com/macos-data-safari-framework-copy/" stringByAppendingString:NSUUID.UUID.UUIDString.lowercaseString];
    NSDictionary *before = InspectPlist(path, url, &error);
    if (!before || [before[@"fixtureCount"] unsignedIntegerValue] != 0) return 11;
    id leaf = CreateFixture(context, url, &error);
    if (!leaf) return 12;
    int createSave = SaveGroup(context);
    NSDictionary *created = InspectPlist(path, url, &error);
    BOOL createOK = created && [created[@"fixtureCount"] unsignedIntegerValue] == 1 &&
        [created[@"matchingAddCount"] unsignedIntegerValue] == 1;
    NSString *uuid = [created[@"fixtureUUIDs"] firstObject];
    id (*find)(id, SEL, id) = (void *)objc_msgSend;
    id savedLeaf = uuid ? find(context[@"group"], NSSelectorFromString(@"bookmarkForUUID:"), uuid) : nil;
    if (!savedLeaf || !RemoveFixture(context, savedLeaf, &error)) return 13;
    int cleanupSave = SaveGroup(context);
    NSDictionary *cleaned = InspectPlist(path, url, &error);
    BOOL cleanupOK = cleaned && [cleaned[@"fixtureCount"] unsignedIntegerValue] == 0;
    printf("{\"mode\":\"copy_roundtrip\",\"createSaveResult\":%d,\"cleanupSaveResult\":%d,\"addRecordConfirmed\":%s,\"zeroResidue\":%s,\"syncRequests\":0}\n",
           createSave, cleanupSave, createOK ? "true" : "false", cleanupOK ? "true" : "false");
    return createOK && cleanupOK ? 0 : 14;
}

static int LiveCreate(NSString *path, NSString *receiptPath, NSString *session, NSString *confirmation) {
    if (![confirmation isEqual:@"CREATE SAFARI PRIVATE FRAMEWORK FIXTURE"]) return 20;
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Safari"].count > 0) return 21;
    if (!IsSafeRegularOwnedFile(path) || [[NSFileManager defaultManager] fileExistsAtPath:receiptPath]) return 22;
    NSDictionary *directoryAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:receiptPath.stringByDeletingLastPathComponent error:nil];
    if (([directoryAttributes[NSFilePosixPermissions] unsignedShortValue] & 0777) != 0700) return 23;

    NSString *error = nil;
    NSDictionary *context = LoadContext(path, &error);
    if (!context) return 24;
    NSString *url = [@"https://example.com/macos-data-safari-framework/" stringByAppendingString:session.lowercaseString];
    NSDictionary *before = InspectPlist(path, url, &error);
    if (!before || [before[@"fixtureCount"] unsignedIntegerValue] != 0) return 25;
    id leaf = CreateFixture(context, url, &error);
    if (!leaf) return 26;
    int saveResult = SaveGroup(context);
    NSDictionary *created = InspectPlist(path, url, &error);
    BOOL addConfirmed = created && [created[@"fixtureCount"] unsignedIntegerValue] == 1 &&
        [created[@"matchingAddCount"] unsignedIntegerValue] == 1 &&
        [created[@"fixtureUUIDs"] count] == 1;
    if (!addConfirmed) {
        NSString *rollbackUUID = [created[@"fixtureUUIDs"] firstObject];
        id (*find)(id, SEL, id) = (void *)objc_msgSend;
        id savedLeaf = rollbackUUID ? find(context[@"group"], NSSelectorFromString(@"bookmarkForUUID:"), rollbackUUID) : leaf;
        BOOL removed = savedLeaf && RemoveFixture(context, savedLeaf, &error);
        int rollbackSave = removed ? SaveGroup(context) : -1;
        NSDictionary *rolledBack = InspectPlist(path, url, &error);
        BOOL zeroResidue = rolledBack && [rolledBack[@"fixtureCount"] unsignedIntegerValue] == 0;
        printf("{\"mode\":\"live_create\",\"addRecordConfirmed\":false,\"rolledBack\":%s,\"rollbackSaveResult\":%d,\"syncRequests\":0}\n",
               zeroResidue ? "true" : "false", rollbackSave);
        return zeroResidue ? 27 : 28;
    }

    NSString *uuid = [created[@"fixtureUUIDs"] firstObject];
    NSMutableDictionary *receipt = [@{
        @"schemaVersion": @1,
        @"sessionID": session.lowercaseString,
        @"fixtureURL": url,
        @"fixtureTitle": FixtureTitle,
        @"fixtureUUID": uuid,
        @"stage": @"created_saved_sync_not_requested",
        @"createSaveResult": @(saveResult),
        @"syncRequestAttempts": @0,
        @"cleanupSyncRequestAttempts": @0
    } mutableCopy];
    if (!WriteReceipt(receiptPath, receipt, &error)) return 29;
    RequestSync(context);
    receipt[@"stage"] = @"sync_requested_remote_pending";
    receipt[@"syncRequestAttempts"] = @1;
    if (!WriteReceipt(receiptPath, receipt, &error)) return 30;
    printf("{\"mode\":\"live_create\",\"fixtureCount\":1,\"addRecordConfirmed\":true,\"saveResult\":%d,\"syncRequests\":1,\"outcome\":\"remote_pending\"}\n", saveResult);
    return 0;
}

static int LiveCleanup(NSString *path, NSString *receiptPath, NSString *confirmation) {
    if (![confirmation isEqual:@"CLEAN SAFARI PRIVATE FRAMEWORK FIXTURE"]) return 40;
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Safari"].count > 0) return 41;
    NSData *receiptData = [NSData dataWithContentsOfFile:receiptPath];
    NSMutableDictionary *receipt = [[NSJSONSerialization JSONObjectWithData:receiptData options:NSJSONReadingMutableContainers error:nil] mutableCopy];
    if (!receipt || [receipt[@"cleanupSyncRequestAttempts"] integerValue] != 0) return 42;
    NSString *url = receipt[@"fixtureURL"];
    NSString *uuid = receipt[@"fixtureUUID"];
    NSString *error = nil;
    NSDictionary *context = LoadContext(path, &error);
    if (!context) return 43;
    id (*find)(id, SEL, id) = (void *)objc_msgSend;
    id leaf = find(context[@"group"], NSSelectorFromString(@"bookmarkForUUID:"), uuid);
    if (!leaf) return 44;
    if (!RemoveFixture(context, leaf, &error)) return 45;
    int saveResult = SaveGroup(context);
    NSDictionary *cleaned = InspectPlist(path, url, &error);
    if (!cleaned || [cleaned[@"fixtureCount"] unsignedIntegerValue] != 0) return 46;
    receipt[@"stage"] = @"cleanup_saved_sync_not_requested";
    receipt[@"cleanupSaveResult"] = @(saveResult);
    if (!WriteReceipt(receiptPath, receipt, &error)) return 47;
    RequestSync(context);
    receipt[@"stage"] = @"cleanup_sync_requested_remote_pending";
    receipt[@"cleanupSyncRequestAttempts"] = @1;
    if (!WriteReceipt(receiptPath, receipt, &error)) return 48;
    printf("{\"mode\":\"live_cleanup\",\"fixtureCount\":0,\"saveResult\":%d,\"syncRequests\":1,\"outcome\":\"cleanup_remote_pending\"}\n", saveResult);
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (!LoadFrameworks()) return 2;
        NSMutableDictionary<NSString *, NSString *> *arguments = [NSMutableDictionary dictionary];
        NSString *mode = nil;
        for (int i = 1; i < argc; i++) {
            NSString *value = [NSString stringWithUTF8String:argv[i]];
            if ([value isEqual:@"--copy-roundtrip"] || [value isEqual:@"--live-create"] || [value isEqual:@"--live-cleanup"]) {
                mode = value;
            } else if ([value hasPrefix:@"--"] && i + 1 < argc) {
                arguments[value] = [NSString stringWithUTF8String:argv[++i]];
            }
        }
        @try {
            if ([mode isEqual:@"--copy-roundtrip"] && arguments[@"--path"]) {
                return CopyRoundTrip(arguments[@"--path"]);
            }
            if ([mode isEqual:@"--live-create"] && arguments[@"--path"] && arguments[@"--receipt"] && arguments[@"--session"]) {
                return LiveCreate(arguments[@"--path"], arguments[@"--receipt"], arguments[@"--session"], arguments[@"--confirm"]);
            }
            if ([mode isEqual:@"--live-cleanup"] && arguments[@"--path"] && arguments[@"--receipt"]) {
                return LiveCleanup(arguments[@"--path"], arguments[@"--receipt"], arguments[@"--confirm"]);
            }
        } @catch (NSException *exception) {
            printf("{\"error\":\"private_framework_exception\",\"retryAllowed\":false}\n");
            return 90;
        }
        return 1;
    }
}
