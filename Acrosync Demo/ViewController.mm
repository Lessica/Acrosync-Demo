//
//  ViewController.m
//  Acrosync Demo
//
//  Created by Zheng on 15/7/17.
//  Copyright © 2015年 Zheng. All rights reserved.
//

#include "rsync_client.h"

#include "rsync_entry.h"
#include "rsync_file.h"
#include "rsync_log.h"
#include "rsync_pathutil.h"
#include "rsync_socketutil.h"
#include "rsync_sshio.h"
#include "rsync_socketio.h"

#include <libssh2.h>
#include <openssl/md5.h>

#include <string>
#include <vector>

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sstream>

#import "ViewController.h"

@interface ViewController () <UITextFieldDelegate>
@property (weak, nonatomic) IBOutlet UITextField *moduleField;
@property (strong, nonatomic) IBOutlet UIView *mainView;
@property (weak, nonatomic) IBOutlet UISwitch *sshSwitch;
@property (weak, nonatomic) IBOutlet UISwitch *uploadSwitch;
@property (weak, nonatomic) IBOutlet UIButton *testButton;
@property (weak, nonatomic) IBOutlet UITextField *serverField;
@property (weak, nonatomic) IBOutlet UITextField *userField;
@property (weak, nonatomic) IBOutlet UITextField *passwordField;
@property (weak, nonatomic) IBOutlet UITextField *remoteField;
@property (weak, nonatomic) IBOutlet UITextField *localField;
@property (weak, nonatomic) IBOutlet UITextView *logField;
@property (weak, nonatomic) IBOutlet UIButton *cancelButton;
@property (weak, nonatomic) IBOutlet UITextField *portField;
@property (weak, nonatomic) IBOutlet UISwitch *debugSwitch;
@property (weak, nonatomic) IBOutlet UIProgressView *progressView;
- (void) myThreadMain;
@end

@implementation ViewController 

BOOL transfer = NO;
int g_cancelFlag = 0;
int64_t totalBytes = 0;
int64_t physicalBytes = 0;
int64_t logicalBytes = 0;
int64_t skippedBytes = 0;
NSTimer *_timer;

// Standard Output Redirection
- (void)redirectNotificationHandle:(NSNotification *)nf {
    NSData *data = [[nf userInfo] objectForKey:NSFileHandleNotificationDataItem];
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    self.logField.text = [NSString stringWithFormat:@"%@\n%@", str, self.logField.text];
    
    [[nf object] readInBackgroundAndNotify];
}

- (void)redirectSTD:(int)fd {
    NSPipe *pipe = [NSPipe pipe];
    NSFileHandle *pipeReadHandle = [pipe fileHandleForReading] ;
    dup2([[pipe fileHandleForWriting] fileDescriptor], fd) ;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(redirectNotificationHandle:)
                                                 name:NSFileHandleReadCompletionNotification
                                               object:pipeReadHandle] ;
    [pipeReadHandle readInBackgroundAndNotify];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self redirectSTD:STDERR_FILENO];
    [self redirectSTD:STDOUT_FILENO];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    self.logField.text = @"Ready.\n";
}

- (void)refresh {
    if (transfer) {
        NSLog(@"%lld/%lld Bytes", physicalBytes, totalBytes);
        if (totalBytes > 0) {
            [self.progressView setProgress:((float)physicalBytes / totalBytes) animated:YES];
        }
    } else {
        totalBytes = physicalBytes = logicalBytes = skippedBytes = 0;
        [self.progressView setProgress:0 animated:YES];
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// Main Sync Thread
- (void) myThreadMain {
    rsync::SocketUtil::startup();
    
    BOOL sshEnabled = self.sshSwitch.on;
    if (sshEnabled) {
        int rc = libssh2_init(0);
        if (rc != 0) {
            LOG_ERROR(LIBSSH2_INIT) << "libssh2 initialization failed: " << rc << LOG_END
            return;
        }
    }
    
    const char *server = [[self.serverField text] UTF8String];
    const char *user = [[self.userField text] UTF8String];
    const char *password = [[self.passwordField text] UTF8String];
    int port = [[self.portField text] intValue];
    
    std::string remoteDir = [[self.remoteField text] UTF8String];
    std::string module = [self.moduleField.text UTF8String];
    NSString *localPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    std::string localDir = rsync::PathUtil::join([localPath UTF8String], [[self.localField text] UTF8String]);
    std::string temporaryFile = rsync::PathUtil::join([localPath UTF8String], "acrosync.part");
    
    if (self.debugSwitch.on) {
        rsync::Log::setLevel(rsync::Log::Debug);
    } else {
        rsync::Log::setLevel(rsync::Log::Fatal);
    }
    
    try {
        if (sshEnabled) {
            rsync::SSHIO sshio;
            sshio.connect(server, port, user, password, 0, 0);
            
            rsync::Client client(&sshio, "rsync", 32, &g_cancelFlag);
            if (!self.uploadSwitch.on) {
                client.download(localDir.c_str(), remoteDir.c_str(), temporaryFile.c_str());
            } else {
                client.upload(localDir.c_str(), remoteDir.c_str());
            }
        } else {
            rsync::SocketIO io;
            NSLog(@"Connect %s...", server);
            io.connect(server, port, user, password, module.c_str());
            rsync::Client client(&io, "rsync", 29, &g_cancelFlag);
            if (!self.uploadSwitch.on) {
                client.setDeletionEnabled(true);
                client.setSpeedLimits(50, 50);
                client.setStatsAddresses(&totalBytes, &physicalBytes, &logicalBytes, &skippedBytes);
                transfer = YES;
                client.download(localDir.c_str(), remoteDir.c_str(), temporaryFile.c_str());
                [self refresh];
                transfer = NO;
                NSLog(@"Transfer ended, totalBytes %lld, physicalBytes %lld, logicalBytes %lld, skippedBytes %lld.", totalBytes, physicalBytes, logicalBytes, skippedBytes);
            } else {
                client.upload(localDir.c_str(), remoteDir.c_str());
            }
        }
    } catch (rsync::Exception &e) {
        transfer = NO;
        LOG_ERROR(RSYNC_ERROR) << "Sync failed: " << e.getMessage() << LOG_END
    }
    
    if (sshEnabled) {
        libssh2_exit();
    }
    rsync::SocketUtil::cleanup();
}

- (IBAction)testButtonTapped:(id)sender {
    [self.view endEditing:YES];
    g_cancelFlag = 0;
    NSThread* myThread = [[NSThread alloc] initWithTarget:self
                                                 selector:@selector(myThreadMain)
                                                   object:nil];
    [myThread start];  // Actually create the thread
}

- (IBAction)cancelTapped:(id)sender {
    g_cancelFlag = 1;
    transfer = NO;
    [self.view endEditing:YES];
}

- (IBAction)serverReturn:(id)sender {
    [self.portField becomeFirstResponder];
}

- (IBAction)userReturn:(id)sender {
    [self.moduleField becomeFirstResponder];
}

- (IBAction)passwordReturn:(id)sender {
    [self.remoteField becomeFirstResponder];
}

- (IBAction)remoteReturn:(id)sender {
    [self.localField becomeFirstResponder];
}

- (IBAction)localReturn:(id)sender {
    [self.logField resignFirstResponder];
}

- (IBAction)portReturn:(id)sender {
    [self.userField becomeFirstResponder];
}

- (IBAction)moduleReturn:(id)sender {
    [self.passwordField becomeFirstResponder];
}


- (IBAction)sshTriggered:(id)sender {
    if (self.sshSwitch.on) {
        self.portField.text = @"58422";
    } else {
        self.portField.text = @"873";
    }
}
@end
