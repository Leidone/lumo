// Now Playing bridge for Lumo's Dynamic Island.
//
// Since macOS 15.4 MediaRemote only answers Apple-signed processes, so Lumo loads this library
// into /usr/bin/perl (see NowPlayingService.swift) and talks to it over a pipe:
//   stdout: one JSON object per line ({"type":"info",...} or {"type":"none"})
//   stdin:  commands — toggle, play, pause, next, previous, seek <seconds>, refresh
// The process exits as soon as Lumo closes the pipe.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <unistd.h>

typedef void (*MRGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetClient)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientString)(id);
typedef void (*MRGetPID)(dispatch_queue_t, void (^)(int));
typedef void (*MRRegister)(dispatch_queue_t);
typedef Boolean (*MRSendCommand)(int, CFDictionaryRef);
typedef void (*MRSetElapsed)(double);

static MRGetInfo getInfo;
static MRGetClient getClient;
static MRClientString clientBundle;
static MRClientString clientParentBundle;
static MRGetPID getPID;
static MRSendCommand sendCommand;
static MRSetElapsed setElapsed;
static dispatch_queue_t queue;
static NSUInteger lastArtworkHash;
static BOOL refreshScheduled;

static void emit(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!data) return;
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id value(NSDictionary *info, NSString *key) {
    id item = info[key];
    return item ?: [NSNull null];
}

static void refresh(void) {
    getInfo(queue, ^(CFDictionaryRef raw) {
        NSDictionary *info = (__bridge NSDictionary *)raw;
        NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
        if (title.length == 0) {
            lastArtworkHash = 0;
            emit(@{@"type": @"none"});
            return;
        }
        NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        NSMutableDictionary *out = [@{
            @"type": @"info",
            @"title": title,
            @"artist": value(info, @"kMRMediaRemoteNowPlayingInfoArtist"),
            @"album": value(info, @"kMRMediaRemoteNowPlayingInfoAlbum"),
            @"duration": value(info, @"kMRMediaRemoteNowPlayingInfoDuration"),
            @"elapsed": value(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime"),
            @"rate": value(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate"),
            @"timestamp": timestamp ? @(timestamp.timeIntervalSince1970) : @([NSDate date].timeIntervalSince1970),
        } mutableCopy];

        NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        NSUInteger hash = artwork.length ? (artwork.length ^ artwork.hash) : 0;
        if (hash != lastArtworkHash) {
            lastArtworkHash = hash;
            out[@"artwork"] = artwork.length ? [artwork base64EncodedStringWithOptions:0] : @"";
        }

        getClient(queue, ^(id client) {
            if (client) {
                NSString *parent = clientParentBundle ? (__bridge NSString *)clientParentBundle(client) : nil;
                NSString *bundle = clientBundle ? (__bridge NSString *)clientBundle(client) : nil;
                out[@"bundle"] = parent.length ? parent : (bundle ?: [NSNull null]);
            }
            getPID(queue, ^(int pid) {
                out[@"pid"] = @(pid);
                emit(out);
            });
        });
    });
}

static void scheduleRefresh(void) {
    if (refreshScheduled) return;
    refreshScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), queue, ^{
        refreshScheduled = NO;
        refresh();
    });
}

static void handle(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *command = parts.firstObject;
    // MRMediaRemoteCommand values: play 0, pause 1, toggle 2, next 4, previous 5.
    NSDictionary<NSString *, NSNumber *> *codes = @{@"play": @0, @"pause": @1, @"toggle": @2, @"next": @4, @"previous": @5};
    if (codes[command]) {
        sendCommand(codes[command].intValue, NULL);
    } else if ([command isEqualToString:@"seek"] && parts.count > 1 && setElapsed) {
        setElapsed(parts[1].doubleValue);
    } else if ([command isEqualToString:@"refresh"]) {
        refresh();
        return;
    }
    scheduleRefresh();
}

static dispatch_source_t commandSource;

static void readCommands(void) {
    commandSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
    NSMutableData *buffer = [NSMutableData data];
    NSData *newlineData = [NSData dataWithBytes:"\n" length:1];
    dispatch_source_set_event_handler(commandSource, ^{
        char chunk[512];
        ssize_t count = read(STDIN_FILENO, chunk, sizeof(chunk));
        if (count <= 0) exit(0); // Lumo went away.
        [buffer appendBytes:chunk length:(NSUInteger)count];
        while (YES) {
            NSRange newline = [buffer rangeOfData:newlineData options:0 range:NSMakeRange(0, buffer.length)];
            if (newline.location == NSNotFound) break;
            NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, newline.location)];
            [buffer replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
            NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
            NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (trimmed.length) handle(trimmed);
        }
    });
    dispatch_resume(commandSource);
}

static dispatch_source_t safetyTimer;

/// Entry point called from perl via DynaLoader; never returns.
void lumo_nowplaying_main(void) {
    void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!framework) exit(2);
    getInfo = (MRGetInfo)dlsym(framework, "MRMediaRemoteGetNowPlayingInfo");
    getClient = (MRGetClient)dlsym(framework, "MRMediaRemoteGetNowPlayingClient");
    clientBundle = (MRClientString)dlsym(framework, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundle = (MRClientString)dlsym(framework, "MRNowPlayingClientGetParentAppBundleIdentifier");
    getPID = (MRGetPID)dlsym(framework, "MRMediaRemoteGetNowPlayingApplicationPID");
    sendCommand = (MRSendCommand)dlsym(framework, "MRMediaRemoteSendCommand");
    setElapsed = (MRSetElapsed)dlsym(framework, "MRMediaRemoteSetElapsedTime");
    MRRegister registerNotifications = (MRRegister)dlsym(framework, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getClient || !getPID || !sendCommand || !registerNotifications) exit(3);

    queue = dispatch_queue_create("lumo.nowplaying", DISPATCH_QUEUE_SERIAL);
    registerNotifications(queue);
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(queue, ^{ scheduleRefresh(); });
        }];
    }
    readCommands();
    // A slow safety net in case a player forgets to post a change.
    safetyTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(safetyTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 15 * NSEC_PER_SEC, 2 * NSEC_PER_SEC);
    dispatch_source_set_event_handler(safetyTimer, ^{ refresh(); });
    dispatch_resume(safetyTimer);
    // MediaRemote posts its notifications on the main run loop.
    CFRunLoopRun();
    exit(0);
}
