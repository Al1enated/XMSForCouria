#import <Foundation/Foundation.h>
#import <substrate.h>
#import <CaptainHook.h>
#import <Couria/Couria.h>
#import <sys/sysctl.h>
#import <sys/socket.h>
#import <netinet/in.h>

#define WhatsAppForCouriaIdentifier @"me.qusic.whatsappforcouria"
#define SpringBoardIdentifier @"com.apple.springboard"
#define BackBoardIdentifier @"com.apple.backboardd"
#define WhatsAppIdentifier @"net.whatsapp.WhatsApp"
#define UserDefaultsPlist @"/var/mobile/Library/Preferences/me.qusic.whatsappforcouria.plist"
#define UserDefaultsChangedNotification CFSTR("me.qusic.whatsappforcouria.UserDefaultsChanged")
#define ApplicationDidExitNotification CFSTR("me.qusic.whatsappforcouria.ApplicationDidExit")
#define UserIDKey @"UserID"
#define MessageKey @"Message"
#define KeepAliveKey @"KeepAlive"
#define SocketPortKey @"Temp"

typedef NS_ENUM(SInt8, CouriaWhatsAppServiceMessageID) {
    GetNickname,
    GetAvatar,
    GetMessages,
    GetContacts,
    SendMessage,
    MarkRead
};

#pragma mark - Headers

@interface CouriaWhatsAppMessage : NSObject <CouriaMessage, NSSecureCoding>
@property(retain) NSString *text;
@property(retain) id media;
@property(assign) BOOL outgoing;
@end

@interface CouriaWhatsAppHandler : NSObject <CouriaDataSource, CouriaDelegate>
+ (instancetype)sharedInstance;
@end

@interface UIApplication (Private)
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

@interface BBBulletin : NSObject
@property(retain, nonatomic) NSDictionary *context;
@end

#ifdef __cplusplus
extern "C" {
#endif
    int xpc_connection_get_pid(id connection);
#ifdef __cplusplus
}
#endif

typedef NS_ENUM(NSUInteger, BKSProcessAssertionReason)
{
    kProcessAssertionReasonAudio = 1,
    kProcessAssertionReasonLocation,
    kProcessAssertionReasonExternalAccessory,
    kProcessAssertionReasonFinishTask,
    kProcessAssertionReasonBluetooth,
    kProcessAssertionReasonNetworkAuthentication,
    kProcessAssertionReasonBackgroundUI,
    kProcessAssertionReasonInterAppAudioStreaming,
    kProcessAssertionReasonViewServices
};

typedef NS_OPTIONS(NSUInteger, ProcessAssertionFlags)
{
    ProcessAssertionFlagNone = 0,
    ProcessAssertionFlagPreventSuspend         = 1 << 0,
    ProcessAssertionFlagPreventThrottleDownCPU = 1 << 1,
    ProcessAssertionFlagAllowIdleSleep         = 1 << 2,
    ProcessAssertionFlagWantsForegroundResourcePriority  = 1 << 3
};

@interface BKSProcessAssertion : NSObject
@property(readonly, assign, nonatomic) BOOL valid;
- (id)initWithPID:(int)pid flags:(unsigned)flags reason:(unsigned)reason name:(id)name withHandler:(id)handler;
- (id)initWithBundleIdentifier:(id)bundleIdentifier flags:(unsigned)flags reason:(unsigned)reason name:(id)name withHandler:(id)handler;
@end

@interface BKApplication : NSObject
@property(readonly, assign, nonatomic) NSString *bundleIdentifier;
@end

@interface BKWorkspaceServer : NSObject
- (void)applicationDidActivate:(BKApplication *)application withInfo:(id)info;
- (void)applicationDidExit:(BKApplication *)application withInfo:(id)info;
@end

@interface WAContact : NSObject
@property(retain, nonatomic) NSString *fullName;
@end

@interface WAPhone : NSObject
@property(retain, nonatomic) WAContact *contact;
@property(retain, nonatomic) NSString* whatsAppID;
@end

@interface WAFavorite : NSObject
@property (nonatomic, retain) WAPhone *phone;
@end

@interface WAGroupInfo : NSObject
@property(retain, nonatomic) NSString *picturePath;
@end

@interface WAChatSession : NSObject
@property(retain, nonatomic) NSString *contactJID;
@property(retain, nonatomic) NSString *partnerName;
@property(retain, nonatomic) WAGroupInfo *groupInfo;
@property(retain, nonatomic) NSNumber *unreadCount;
@end

@interface WAMediaItem : NSObject
@property(retain, nonatomic) NSString *mediaLocalPath;
@end

@interface WAGroupMember : NSObject
@property(retain, nonatomic) NSString *contactName;
@end

typedef NS_ENUM(NSInteger, WhatsAppMessageType) {
    TextMessage  = 0,
    PhotoMessage = 1,
    MovieMessage = 2
};

@interface WAMessage : NSObject
@property(retain, nonatomic) NSString *text;
@property(retain, nonatomic) NSNumber *messageType;
@property(retain, nonatomic) WAMediaItem *mediaItem;
@property(retain, nonatomic) NSNumber *isFromMe;
@property(retain, nonatomic) NSDate *messageDate;
@property(retain, nonatomic) NSNumber *groupEventType;
@property(retain, nonatomic) WAGroupMember *groupMember;
@end

@class NSManagedObjectID;

@interface WAContactsStorage : NSObject
- (NSArray *)favorites;
- (WAFavorite *)favoriteWithObjectID:(NSManagedObjectID *)objectID;
- (WAContact *)contactForJID:(NSString *)jid;
- (WAPhone *)phoneWithObjectID:(NSManagedObjectID *)objectID;
- (UIImage *)profilePictureForJID:(NSString *)jid;
@end

@interface WAChatStorage : NSObject
- (NSArray *)chatSessionsWithBroadcast:(BOOL)broadcast;
- (WAChatSession *)existingChatSessionForJID:(NSString *)jid;
- (WAChatSession *)createChatSessionForContact:(WAContact *)contact JID:(NSString *)jid;
- (NSArray *)messagesForSession:(WAChatSession *)session startOffset:(NSUInteger)offset limit:(NSUInteger)limit;
- (void)storeModifiedChatSession:(WAChatSession *)session;
- (WAMessage *)messageWithText:(NSString *)text inChatSession:(WAChatSession *)chatSession isBroadcast:(BOOL)broadcast;
- (void)sendMessageWithImage:(UIImage *)image ofIndex:(NSInteger)index totalCount:(NSUInteger)count inChatSession:(WAChatSession *)chatSession completion:(id)completion;
- (void)sendVideoAtURL:(NSURL *)movieURL inChatSession:(WAChatSession *)chatSession completion:(id)completion;
@end

@interface ChatManager : NSObject
@property(readonly, assign, nonatomic) WAContactsStorage *contactsStorage;
@property(readonly, assign, nonatomic) WAChatStorage *storage;
+ (ChatManager *)sharedManager;
@end

#pragma mark - Globals

static NSDictionary *userDefaults;
static NSInteger socketPort;
static BKSProcessAssertion *processAssertion; // Keep WhatsApp running and prevent it from suspended
static CFSocketRef listeningSocket; // Use tcp socket as a workaround, since mach-register in sandboxed apps is not allowed in iOS 7
static WAContactsStorage *contactsStorage;
static WAChatStorage *chatStorage;

#pragma mark - Functions

static int PIDForProcessNamed(NSString *passedInProcessName)
{
    int pid = 0;
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    u_int miblen = 4;
    size_t size;
    int st = sysctl(mib, miblen, NULL, &size, NULL, 0);
    struct kinfo_proc * process = NULL;
    struct kinfo_proc * newprocess = NULL;
    do {
        size += size / 10;
        newprocess = (kinfo_proc *)realloc(process, size);
        if (!newprocess) {
            if (process) {
                free(process);
            }
            return 0;
        }
        process = newprocess;
        st = sysctl(mib, miblen, process, &size, NULL, 0);
    } while (st == -1 && errno == ENOMEM);
    if (st == 0) {
        if (size % sizeof(struct kinfo_proc) == 0) {
            u_long nprocess = size / sizeof(struct kinfo_proc);
            if (nprocess) {
                for (long i = nprocess - 1; i >= 0; i--) {
                    NSString * processName = [[NSString alloc] initWithFormat:@"%s", process[i].kp_proc.p_comm];
                    if ([processName rangeOfString:passedInProcessName].location != NSNotFound) {
                        pid = process[i].kp_proc.p_pid;
                    }
                }
                free(process);
            }
        }
    }
    return pid;
}

static inline BOOL appIsRunning()
{
    return (PIDForProcessNamed(@"WhatsApp") > 0);
}

static inline void launchApp()
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void){
        [[UIApplication sharedApplication]launchApplicationWithIdentifier:WhatsAppIdentifier suspended:YES];
    });
}

static BOOL readBytes(CFReadStreamRef readStream, void *buffer, NSUInteger length)
{
    NSUInteger read = 0;
    while (read < length) {
        NSInteger result = CFReadStreamRead(readStream, ((UInt8 *)buffer) + read, length - read);
        if (result > 0) {
            read += result;
        } else {
            return NO;
        }
    }
    return YES;
}

static BOOL writeBytes(CFWriteStreamRef writeStream, const void *bytes, NSUInteger length)
{
    NSUInteger written = 0;
    while (written < length) {
        NSInteger result = CFWriteStreamWrite(writeStream, ((const UInt8 *)bytes) + written, length - written);
        if (result > 0) {
            written += result;
        } else {
            return NO;
        }
    }
    return YES;
}

static NSData *sendMessage(CouriaWhatsAppServiceMessageID messageId, NSData *messageData)
{
    if (!appIsRunning()) {
        return nil;
    }
    NSData *responseData = nil;
    CFReadStreamRef readStream;
    CFWriteStreamRef writeStream;
    CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, CFSTR("127.0.0.1"), (UInt32)socketPort, &readStream, &writeStream);
    if (readStream && writeStream) {
        CFReadStreamOpen(readStream);
        CFWriteStreamOpen(writeStream);
        UInt64 messageLength = messageData.length;
        BOOL writeDone =
        writeBytes(writeStream, &messageId, sizeof(CouriaWhatsAppServiceMessageID)) &&
        writeBytes(writeStream, &messageLength, sizeof(UInt64)) &&
        writeBytes(writeStream, messageData.bytes, messageLength);
        if (writeDone) {
            UInt64 dataLength = 0;
            if (readBytes(readStream, &dataLength, sizeof(UInt64))) {
                void *buffer = malloc(dataLength);
                if (buffer != NULL && readBytes(readStream, buffer, dataLength)) {
                    responseData = [NSData dataWithBytesNoCopy:buffer length:dataLength freeWhenDone:YES];
                }
            }
        }
        CFReadStreamClose(readStream);
        CFWriteStreamClose(writeStream);
    }
    if (readStream) {
        CFRelease(readStream);
    }
    if (writeStream) {
        CFRelease(writeStream);
    }
    return responseData ? : [NSData data];
}

static void userDefaultsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    userDefaults = [NSDictionary dictionaryWithContentsOfFile:UserDefaultsPlist];
    socketPort = [userDefaults[SocketPortKey]integerValue];
    if ([userDefaults[KeepAliveKey]boolValue]) {
        launchApp();
    }
}

static void applicationDidExitCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
    if ([userDefaults[KeepAliveKey]boolValue]) {
        launchApp();
    }
}

#pragma mark - Implementations

@implementation CouriaWhatsAppMessage

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [self init];
    if (self) {
        _text = [aDecoder decodeObjectOfClass:NSString.class forKey:@"Text"];
        _outgoing = [[aDecoder decodeObjectOfClass:NSNumber.class forKey:@"Outgoing"]boolValue];
        _media = [aDecoder decodeObjectOfClasses:[NSSet setWithObjects:UIImage.class, NSURL.class, nil] forKey:@"Media"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_text forKey:@"Text"];
    [aCoder encodeObject:@(_outgoing) forKey:@"Outgoing"];
    if ([_media isKindOfClass:UIImage.class] || [_media isKindOfClass:NSURL.class]) {
        [aCoder encodeObject:_media forKey:@"Media"];
    }
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end

@implementation CouriaWhatsAppHandler

+ (instancetype)sharedInstance
{
    CouriaWhatsAppHandler *sharedInstance;
    if (sharedInstance == nil) {
        sharedInstance = [[CouriaWhatsAppHandler alloc]init];
    }
    return sharedInstance;
}

- (NSString *)getUserIdentifier:(BBBulletin *)bulletin
{
    if (!appIsRunning()) {
        return nil;
    }
    NSString *notificationType = bulletin.context[@"notificationType"];
    NSDictionary *userInfo = bulletin.context[@"userInfo"];
    NSString *userIdentifier = nil;
    if ([notificationType isEqualToString:@"AppNotificationLocal"]) {
        userIdentifier = userInfo[@"jid"];
    } else if ([notificationType isEqualToString:@"AppNotificationRemote"]) {
        NSString *u = userInfo[@"aps"][@"u"];
        if ([u rangeOfString:@"-"].location == NSNotFound) {
            userIdentifier = [NSString stringWithFormat:@"%@@s.whatsapp.net", u];
        } else {
            userIdentifier = [NSString stringWithFormat:@"%@@g.us", u];
        }
    }
    return userIdentifier;
}

- (NSString *)getNickname:(NSString *)userIdentifier
{
    if (!appIsRunning()) {
        return nil;
    }

    NSData *replyData = sendMessage(GetNickname, [userIdentifier dataUsingEncoding:NSUTF8StringEncoding]);
    NSString *nickname = [[NSString alloc]initWithData:replyData encoding:NSUTF8StringEncoding];
    return nickname;
}

- (UIImage *)getAvatar:(NSString *)userIdentifier
{
    if (!appIsRunning()) {
        return nil;
    }
    NSData *replyData = sendMessage(GetAvatar, [userIdentifier dataUsingEncoding:NSUTF8StringEncoding]);
    UIImage *avatar = [UIImage imageWithData:replyData];
    return avatar;
}

- (NSArray *)getMessages:(NSString *)userIdentifier
{
    if (!appIsRunning()) {
        return nil;
    }
    NSData *replyData = sendMessage(GetMessages, [userIdentifier dataUsingEncoding:NSUTF8StringEncoding]);
    NSArray *messages = [NSKeyedUnarchiver unarchiveObjectWithData:replyData];
    return messages;
}

- (NSArray *)getContacts:(NSString *)keyword
{
    if (!appIsRunning()) {
        return nil;
    }
    NSData *replyData = sendMessage(GetContacts, [keyword dataUsingEncoding:NSUTF8StringEncoding]);
    NSArray *contacts = [NSKeyedUnarchiver unarchiveObjectWithData:replyData];
    return contacts;
}

- (void)sendMessage:(id<CouriaMessage>)message toUser:(NSString *)userIdentifier
{
    if (!appIsRunning()) {
        return;
    }
    CouriaWhatsAppMessage *whatsappMessage = [[CouriaWhatsAppMessage alloc]init];
    whatsappMessage.text = message.text;
    whatsappMessage.media = message.media;
    whatsappMessage.outgoing = message.outgoing;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:@{UserIDKey: userIdentifier, MessageKey: whatsappMessage}];
    sendMessage(SendMessage, data);
}

- (void)markRead:(NSString *)userIdentifier
{
    if (!appIsRunning()) {
        return;
    }
    NSData *data = [userIdentifier dataUsingEncoding:NSUTF8StringEncoding];
    sendMessage(MarkRead, data);
}

- (BOOL)canSendPhoto
{
    return YES;
}

- (BOOL)canSendMovie
{
    return YES;
}

@end

#pragma mark - Service

static NSData *serviceCallback(CouriaWhatsAppServiceMessageID messageId, NSData *messageData)
{
    NSData *returnData = nil;
    switch (messageId) {
        case GetNickname: {
            NSString *userIdentifier = [[NSString alloc]initWithData:messageData encoding:NSUTF8StringEncoding];
            NSString *nickname = nil;
            if ([userIdentifier hasSuffix:@"@g.us"]) {
                nickname = [chatStorage existingChatSessionForJID:userIdentifier].partnerName;
            } else {
                nickname = [contactsStorage contactForJID:userIdentifier].fullName;
            }
            if (nickname == nil) {
                nickname = userIdentifier;
            }
            returnData = [nickname dataUsingEncoding:NSUTF8StringEncoding];
            break;
        }
        case GetAvatar: {
            NSString *userIdentifier = [[NSString alloc]initWithData:messageData encoding:NSUTF8StringEncoding];
            UIImage *avatar = nil;
            if ([userIdentifier hasSuffix:@"@g.us"]) {
                avatar = [UIImage imageWithContentsOfFile:[[NSString stringWithFormat:@"~/Library/%@.thumb",[chatStorage existingChatSessionForJID:userIdentifier].groupInfo.picturePath]stringByExpandingTildeInPath]];
                if (avatar == nil) {
                    avatar = [UIImage imageNamed:@"GroupChat.png"];
                }
            } else {
                avatar = [contactsStorage profilePictureForJID:userIdentifier];
                if (avatar == nil) {
                    avatar = [UIImage imageNamed:@"EmptyContact.png"];
                }
            }
            returnData = UIImagePNGRepresentation(avatar);
            break;
        }
        case GetMessages: {
            NSString *userIdentifier = [[NSString alloc]initWithData:messageData encoding:NSUTF8StringEncoding];
            NSArray *messages = [chatStorage messagesForSession:[chatStorage existingChatSessionForJID:userIdentifier] startOffset:0 limit:15];
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if (messages.count > 0) {
                NSMutableArray *whatsappMessages = [NSMutableArray array];
                for (WAMessage *message in messages) {
                    if (message.groupEventType.integerValue != 0) {
                        continue;
                    }
                    CouriaWhatsAppMessage *whatsappMessage = [[CouriaWhatsAppMessage alloc]init];
                    switch (message.messageType.integerValue) {
                        case TextMessage: {
                            whatsappMessage.text = message.text;
                            break;
                        }
                        case PhotoMessage: {
                            WAMediaItem *mediaItem = message.mediaItem;
                            NSString *fullPath = [[NSString stringWithFormat:@"~/Library/%@",mediaItem.mediaLocalPath]stringByExpandingTildeInPath];
                            if ([fileManager fileExistsAtPath:fullPath]) {
                                whatsappMessage.text = @"";
                                whatsappMessage.media = [UIImage imageWithContentsOfFile:fullPath];
                            } else {
                                whatsappMessage.text = @"[Not Downloaded Photo]";
                            }
                            break;
                        }
                        case MovieMessage: {
                            WAMediaItem *mediaItem = message.mediaItem;
                            NSString *fullPath = [[NSString stringWithFormat:@"~/Library/%@",mediaItem.mediaLocalPath]stringByExpandingTildeInPath];
                            if ([fileManager fileExistsAtPath:fullPath]) {
                                whatsappMessage.text = @"";
                                whatsappMessage.media = [NSURL fileURLWithPath:fullPath];
                            } else {
                                whatsappMessage.text = @"[Not Downloaded Movie]";
                            }
                            break;
                        }
                    }
                    if (message.groupMember != nil) {
                        whatsappMessage.text = [NSString stringWithFormat:@"%@: %@", message.groupMember.contactName, whatsappMessage.text];
                    }
                    whatsappMessage.outgoing = message.isFromMe.boolValue;
                    [whatsappMessages insertObject:whatsappMessage atIndex:0];
                }
                returnData = [NSKeyedArchiver archivedDataWithRootObject:whatsappMessages];
            }
            break;
        }
        case GetContacts: {
            NSString *keyword = [[NSString alloc]initWithData:messageData encoding:NSUTF8StringEncoding];
            NSMutableArray *contacts = [NSMutableArray array];
            if (keyword.length == 0) {
                NSArray *chatSessions = [chatStorage chatSessionsWithBroadcast:NO];
                for (WAChatSession *chatSession in chatSessions) {
                    [contacts addObject:chatSession.contactJID];
                }
            } else {
                NSArray *favorites = contactsStorage.favorites;
                for (NSManagedObjectID *favoriteObjectId in favorites) {
                    WAPhone *phone = [contactsStorage favoriteWithObjectID:favoriteObjectId].phone;
                    NSString *fullName = phone.contact.fullName;
                    NSString *whatsAppID = phone.whatsAppID;
                    if ([fullName rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound || [whatsAppID rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
                        [contacts addObject:[NSString stringWithFormat:@"%@@s.whatsapp.net", whatsAppID]];
                    }
                }
            }
            returnData = [NSKeyedArchiver archivedDataWithRootObject:contacts];
            break;
        }
        case SendMessage: {
            NSDictionary *messageDictionary = [NSKeyedUnarchiver unarchiveObjectWithData:messageData];
            NSString *userIdentifier = messageDictionary[UserIDKey];
            CouriaWhatsAppMessage *message = messageDictionary[MessageKey];
            NSString *text = message.text;
            id media = message.media;
            WAChatSession *chatSession = [chatStorage existingChatSessionForJID:userIdentifier];
            if (chatSession == nil) {
                WAContact *contact = [contactsStorage contactForJID:userIdentifier];
                chatSession = [chatStorage createChatSessionForContact:contact JID:userIdentifier];
            }
            if (text.length > 0) {
                [chatStorage messageWithText:text inChatSession:chatSession isBroadcast:NO];
            }
            if (media != nil) {
                if ([media isKindOfClass:UIImage.class]) {
                    [chatStorage sendMessageWithImage:media ofIndex:0 totalCount:1 inChatSession:chatSession completion:^(void){}];
                } else if ([media isKindOfClass:NSURL.class]) {
                    [chatStorage sendVideoAtURL:media inChatSession:chatSession completion:^(void){}];
                }
            }
            break;
        }
        case MarkRead: {
            NSString *userIdentifier = [[NSString alloc]initWithData:messageData encoding:NSUTF8StringEncoding];
            WAChatSession *chatSession = [chatStorage existingChatSessionForJID:userIdentifier];
            chatSession.unreadCount = @(0);
            [chatStorage storeModifiedChatSession:chatSession];
            break;
        }
    }
    return returnData ? : [NSData data];
}

static void socketCallBack(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
    CFSocketNativeHandle socketHandle = *(CFSocketNativeHandle *)data;
    CFReadStreamRef readStream = NULL;
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, socketHandle, &readStream, &writeStream);
    if (readStream && writeStream) {
        CFReadStreamOpen(readStream);
        CFWriteStreamOpen(writeStream);
        CouriaWhatsAppServiceMessageID messageId = -1;
        UInt64 messageLength = 0;
        NSData *messageData;
        BOOL readDone = NO;
        if (readBytes(readStream, &messageId, sizeof(CouriaWhatsAppServiceMessageID)) &&
            readBytes(readStream, &messageLength, sizeof(UInt64))) {
            void *buffer = malloc(messageLength);
            if (buffer != NULL && readBytes(readStream, buffer, messageLength)) {
                messageData = [NSData dataWithBytesNoCopy:buffer length:messageLength freeWhenDone:YES];
                readDone = YES;
            }
        }
        if (readDone) {
            NSData *responseData = serviceCallback(messageId, messageData);
            UInt64 dataLength = responseData.length;
            writeBytes(writeStream, &dataLength, sizeof(UInt64));
            writeBytes(writeStream, responseData.bytes, dataLength);
        }
        CFReadStreamClose(readStream);
        CFWriteStreamClose(writeStream);
    }
    if (readStream) {
        CFRelease(readStream);
    }
    if (writeStream) {
        CFRelease(writeStream);
    }
    close(socketHandle);
}

static void CouriaWhatsAppServiceStart(void)
{
    processAssertion = [[BKSProcessAssertion alloc]initWithBundleIdentifier:WhatsAppIdentifier flags:(ProcessAssertionFlagPreventSuspend | ProcessAssertionFlagPreventThrottleDownCPU | ProcessAssertionFlagAllowIdleSleep | ProcessAssertionFlagWantsForegroundResourcePriority) reason:kProcessAssertionReasonBackgroundUI name:WhatsAppForCouriaIdentifier withHandler:NULL];

    CFSocketRef socket = CFSocketCreate(kCFAllocatorDefault, AF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, &socketCallBack, NULL);
    if (socket == NULL) {
        return;
    }
    static const int yes = 1;
    setsockopt(CFSocketGetNative(socket), SOL_SOCKET, SO_REUSEADDR, (const void *)&yes, sizeof(yes));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(0);
    addr.sin_addr.s_addr = htonl((u_int32_t)0x7F000001);
    if (CFSocketSetAddress(socket, (__bridge CFDataRef)[NSData dataWithBytes:&addr length:sizeof(addr)]) != kCFSocketSuccess) {
        CFSocketInvalidate(socket);
        CFRelease(socket);
        return;
    }
    NSUInteger port = ntohs(((const struct sockaddr_in *)CFDataGetBytePtr(CFSocketCopyAddress(socket)))->sin_port);
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, socket, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CFRelease(source);
    listeningSocket = socket;

    NSMutableDictionary *userDefaults = [NSMutableDictionary dictionary];
    [userDefaults addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:UserDefaultsPlist]];
    userDefaults[SocketPortKey] = @(port);
    [userDefaults writeToFile:UserDefaultsPlist atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), UserDefaultsChangedNotification, NULL, NULL, TRUE);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^(void){
        ChatManager *chatManager = [NSClassFromString(@"ChatManager")sharedManager];
        contactsStorage = chatManager.contactsStorage;
        chatStorage = chatManager.storage;
    });
}

#pragma mark - Hooks

static int (*original_XPConnectionHasEntitlement)(id connection, NSString *entitlement);
static int optimized_XPConnectionHasEntitlement(id connection, NSString *entitlement)
{
    if (xpc_connection_get_pid(connection) == PIDForProcessNamed(@"WhatsApp") && [entitlement isEqualToString:@"com.apple.multitasking.unlimitedassertions"]) {
        return 1;
    } else {
        return original_XPConnectionHasEntitlement(connection, entitlement);
    }
}

CHDeclareClass(BKWorkspaceServer)
CHOptimizedMethod(2, self, void, BKWorkspaceServer, applicationDidExit, BKApplication *, application, withInfo, id ,info)
{
    CHSuper(2, BKWorkspaceServer, applicationDidExit, application, withInfo, info);
    if ([application.bundleIdentifier isEqualToString:WhatsAppIdentifier]) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), ApplicationDidExitNotification, NULL, NULL, TRUE);
    }
}

#pragma mark - Constructor

CHConstructor
{
    @autoreleasepool {
        NSString *applicationIdentifier = [NSBundle mainBundle].bundleIdentifier;
        if ([applicationIdentifier isEqualToString:SpringBoardIdentifier]) {
            Couria *couria = [NSClassFromString(@"Couria") sharedInstance];
            CouriaWhatsAppHandler *handler = [CouriaWhatsAppHandler sharedInstance];
            [couria registerDataSource:handler delegate:handler forApplication:WhatsAppIdentifier];
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, userDefaultsChangedCallback, UserDefaultsChangedNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, applicationDidExitCallback, ApplicationDidExitNotification, NULL, CFNotificationSuspensionBehaviorCoalesce);
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), UserDefaultsChangedNotification, NULL, NULL, TRUE);
        } else if ([applicationIdentifier isEqualToString:BackBoardIdentifier]) {
            dlopen("/System/Library/PrivateFrameworks/XPCObjects.framework/XPCObjects", RTLD_LAZY);
            MSHookFunction(((int *)MSFindSymbol(NULL, "_XPCConnectionHasEntitlement")), (int *)optimized_XPConnectionHasEntitlement, (int **)&original_XPConnectionHasEntitlement);
            CHLoadLateClass(BKWorkspaceServer);
            CHHook(2, BKWorkspaceServer, applicationDidExit, withInfo);
        } else if ([applicationIdentifier isEqualToString:WhatsAppIdentifier]) {
            CouriaWhatsAppServiceStart();
        }
    }
}
