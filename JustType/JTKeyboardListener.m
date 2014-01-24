//
//  JTKeyboardListener.m
//  JustType
//
//  Created by Alexander Koglin on 27.12.13.
//  Copyright (c) 2013 Alexander Koglin. All rights reserved.
//

#import "JTKeyboardListener.h"
#import "JTKeyboardOverlayView.h"
#import "JTKeyboardGestureRecognizer.h"
#import "JTKeyboardHeaders.h"

enum JTKeyboardSwipeDirection {
    JTKeyboardSwipeDirectionNone = 0,
    JTKeyboardSwipeDirectionHorizontal = 1,
    JTKeyboardSwipeDirectionVertical = 2
    };

NSString * const JTKeyboardGestureSwipeLeftLong     = @"JTKeyboardGestureSwipeLeftLong";
NSString * const JTKeyboardGestureSwipeRightLong    = @"JTKeyboardGestureSwipeRightLong";
NSString * const JTKeyboardGestureSwipeLeftShort    = @"JTKeyboardGestureSwipeLeftShort";
NSString * const JTKeyboardGestureSwipeRightShort   = @"JTKeyboardGestureSwipeRightShort";
NSString * const JTKeyboardGestureSwipeUp           = @"JTKeyboardGestureSwipeUp";
NSString * const JTKeyboardGestureSwipeDown         = @"JTKeyboardGestureSwipeDown";

#define SWIPE_LONGSWIPE_WIDTH 100.0
#define SAMPLE_TIME_SECS_INITIAL 0.6
#define SAMPLE_TIME_SECS_MAX 0.3
#define SAMPLE_TIME_SECS_MIDDLE 0.2
#define SAMPLE_TIME_SECS_MIN 0.1

@interface JTKeyboardListener ()

@property (nonatomic, readonly) UIWindow *mainWindow;
@property (nonatomic, readonly) UIWindow *keyboardWindow;
@property (nonatomic, readonly) UIWindow *keyboardView;

@property (nonatomic, retain) UIGestureRecognizer *panGesture;
@property (nonatomic, assign) CGPoint gestureStartingPoint;
@property (nonatomic, assign) CGPoint gestureMovementPoint;
@property (nonatomic, assign) enum JTKeyboardSwipeDirection lastSwipeDirection;
@property (nonatomic, retain) NSString *lastSwipeGestureType;
@property (nonatomic, assign) BOOL panGestureInProgress;

@property (nonatomic, retain) JTKeyboardOverlayView *keyboardOverlayView;
@property (nonatomic, assign, getter = areGesturesEnabled) BOOL enableGestures;

- (void)cleanupViewsAndGestures;
- (void)storeStartingPointWithGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
- (void)sendNotificationForLastSwipeGesture;
- (void)checkGestureResult;
- (void)doPolling;
- (void)stopPollingAndCleanGesture;
- (void)recomputeSwipeDirection;
- (BOOL)keyboardIsAvailable;

@end


@implementation JTKeyboardListener 
@synthesize panGesture = _panGesture;
@synthesize keyboardOverlayView = _keyboardOverlayView;
@synthesize gestureStartingPoint = _gestureStartingPoint;
@synthesize gestureMovementPoint = _gestureMovementPoint;
@synthesize lastSwipeDirection = _lastSwipeDirection;
@synthesize lastSwipeGestureType = _lastSwipeGestureType;
@synthesize panGestureInProgress = _panGestureInProgress;
@synthesize enableVisualHelp = _enableVisualHelp;
@synthesize enableGestures = _enableGestures;

# pragma mark - object lifecycle
+ (id)sharedInstance {
    static JTKeyboardListener *sharedKeyboardListener;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedKeyboardListener = [[JTKeyboardListener alloc] init];
    });
    
    return sharedKeyboardListener;
}

- (id)init {
    self = [super init];
    if (self) {
        self.enableVisualHelp = YES;
    }
    return self;
}

- (void)dealloc {
}

# pragma mark - public methods
- (void)observeKeyboardGestures:(BOOL)activate {
    if (activate) {
        // register for keyboard notifications
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidShow:) 
                                                     name:UIKeyboardDidShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHide:) 
                                                     name:UIKeyboardWillHideNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(textControllerDidProcessGesture:)
                                                     name:JTNotificationTextControllerDidProcessGesture object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [self cleanupViewsAndGestures];
    }
}

# pragma mark - Keyboard handling
- (void)keyboardDidShow:(NSNotification *)notification {
    UIView *keyboardView = self.keyboardView;
    
    if (!keyboardView) {
        NSLog(@"Keyboard view is not at the expected place, \n \
              probably you use incompatible version of iOS. \n \
              The keyboard functionality is skipped");
    }
    
    // add own ABKeyboardOverlayView to KeyboardOverlay (just for giving hints)
    JTKeyboardOverlayView *transparentView = [[JTKeyboardOverlayView alloc] initWithFrame:keyboardView.bounds];
    transparentView.backgroundColor = [UIColor clearColor];
    transparentView.alpha = 1.0;
    transparentView.userInteractionEnabled = NO;
    [keyboardView addSubview:transparentView];
    self.keyboardOverlayView = transparentView;
    
    [self setEnableGestures:YES];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    [self cleanupViewsAndGestures];
}

- (void)cleanupViewsAndGestures {
    // remove all the views and gestures
    [self.keyboardOverlayView removeFromSuperview];
    self.keyboardOverlayView = nil;
    
    [self setEnableGestures:NO];
}

# pragma mark - internal notifications
- (void)textControllerDidProcessGesture:(NSNotification *)notification {
    if (self.isVisualHelpEnabled) {
        NSString *swipeDirection = [notification.userInfo objectForKey:JTNotificationKeyDirection];
        [self.keyboardOverlayView visualizeDirection:swipeDirection];
    }
}

# pragma mark - Gesture recognizers
- (void)panned:(UIGestureRecognizer*)gestureRecognizer {
    
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
        
        self.gestureStartingPoint = [gestureRecognizer locationInView:self.keyboardOverlayView];
        self.gestureMovementPoint = self.gestureStartingPoint;
        self.panGestureInProgress = YES;
        
        // we give it a small time for deciding between a short and a long swipe
        [self performSelector:@selector(checkGestureResult) withObject:nil afterDelay:SAMPLE_TIME_SECS_MIDDLE];
        
    } else if (gestureRecognizer.state == UIGestureRecognizerStateChanged) {
        
        self.gestureMovementPoint = [gestureRecognizer locationInView:self.keyboardOverlayView];
        
    } else if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
        
        self.panGestureInProgress = NO;
        
    } else if (gestureRecognizer.state == UIGestureRecognizerStateFailed ||
               gestureRecognizer.state == UIGestureRecognizerStateCancelled) {
        
        [self stopPollingAndCleanGesture];
    }
}

- (void)checkGestureResult {

    [self recomputeSwipeDirection];
    [self sendNotificationForLastSwipeGesture];

    // now after the first swipe we wait a quite high amount of time until we begin the high-density polling for the 'long-duration swipe'.
    [self performSelector:@selector(doPolling) withObject:nil afterDelay:SAMPLE_TIME_SECS_INITIAL];
}

- (void)doPolling {
    if (self.panGestureInProgress) {
        [self recomputeSwipeDirection];
        [self sendNotificationForLastSwipeGesture];

        NSTimeInterval delay = SAMPLE_TIME_SECS_MIDDLE;
        [self performSelector:@selector(doPolling) withObject:nil afterDelay:delay];
    } else {
        [self stopPollingAndCleanGesture];
    }
}

- (void)stopPollingAndCleanGesture {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    self.gestureStartingPoint = CGPointZero;
    self.gestureMovementPoint = CGPointZero;
    self.lastSwipeGestureType = nil;
    self.lastSwipeDirection = JTKeyboardSwipeDirectionNone;
    self.panGestureInProgress = NO;
}

- (void)storeStartingPointWithGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    // store the starting point
    self.gestureStartingPoint = [gestureRecognizer locationInView:self.keyboardOverlayView];
}

- (void)recomputeSwipeDirection {
    
    CGPoint diffPoint = CGPointMake(self.gestureMovementPoint.x - self.gestureStartingPoint.x,
                                    self.gestureMovementPoint.y - self.gestureStartingPoint.y);

    if (self.lastSwipeDirection == JTKeyboardSwipeDirectionHorizontal) {
        [self determineHorizontalSwipeGestureWithDiff:diffPoint];
        
    } else if (self.lastSwipeDirection == JTKeyboardSwipeDirectionVertical) {
        /* do nothing */
            
    } else if (self.lastSwipeDirection == JTKeyboardSwipeDirectionNone) {
        [self determineSwipeDirectionWithDiff:diffPoint];
        
    }

}

- (void)determineSwipeDirectionWithDiff:(CGPoint)diffPoint {
    CGPoint absDiffPoint = CGPointMake(ABS(diffPoint.x), ABS(diffPoint.y));
    
    if (absDiffPoint.x >= absDiffPoint.y) {
        self.lastSwipeDirection = JTKeyboardSwipeDirectionHorizontal;
        [self determineHorizontalSwipeGestureWithDiff:diffPoint];
        
    } else {
        self.lastSwipeDirection = JTKeyboardSwipeDirectionVertical;
        [self determineVerticalSwipeGestureWithDiff:diffPoint];
    }

}

- (void)determineHorizontalSwipeGestureWithDiff:(CGPoint)diffPoint {
    if (diffPoint.x < 0) {
        if (-diffPoint.x <= SWIPE_LONGSWIPE_WIDTH) {
            self.lastSwipeGestureType = JTKeyboardGestureSwipeLeftShort;
        } else {
            self.lastSwipeGestureType = JTKeyboardGestureSwipeLeftLong;
        }
    } else {
        if (diffPoint.x <= SWIPE_LONGSWIPE_WIDTH) {
            self.lastSwipeGestureType = JTKeyboardGestureSwipeRightShort;
        } else {
            self.lastSwipeGestureType = JTKeyboardGestureSwipeRightLong;
        }
    }
}

- (void)determineVerticalSwipeGestureWithDiff:(CGPoint)diffPoint {
    if (diffPoint.y < 0) {
        self.lastSwipeGestureType = JTKeyboardGestureSwipeUp;
    } else {
        self.lastSwipeGestureType = JTKeyboardGestureSwipeDown;
    }
}

- (void)sendNotificationForLastSwipeGesture {
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:self.lastSwipeGestureType forKey:JTNotificationKeyDirection];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:JTNotificationTextControllerDidRecognizeGesture object:self userInfo:userInfo];
}

- (BOOL)keyboardIsAvailable {
    return [self keyboardView] != nil;
}

# pragma mark - private methods
- (UIWindow *)mainWindow {
    return [[[UIApplication sharedApplication] delegate] window];
}

/*
 * Fetches the keyboard window, this method makes explicit checks
 * if the view hierarchy has not changed in another iOS version.
 */
- (UIWindow *)keyboardWindow {
    NSArray *allWindows = [[UIApplication sharedApplication] windows];
    if ([allWindows count] < 2) return nil;
    
    UIWindow *keyboardWindow = [allWindows objectAtIndex:1];
    NSString *specificWindowClassName = NSStringFromClass([keyboardWindow class]);
    if (![specificWindowClassName isEqualToString:@"UITextEffectsWindow"]) {
        return nil;
    }
    
    return keyboardWindow;
}

/*
 * Fetches the keyboard view, this method makes explicit checks
 * if the view hierarchy has not changed in another iOS version.
 */
- (UIView *)keyboardView {
    UIWindow *keyboardWindow = [self keyboardWindow];
    if (!keyboardWindow) return nil;
    
    NSArray *keyboardWindowSubviews = [keyboardWindow subviews];
    if ([keyboardWindowSubviews count] == 0) return nil;
    
    UIView *keyboardView = [keyboardWindowSubviews objectAtIndex:0];
    NSString *specificViewClassName = NSStringFromClass([keyboardView class]);
    if (![specificViewClassName isEqualToString:@"UIPeripheralHostView"]) {
        return nil;
    }

    return keyboardView;
}

# pragma mark - gesture recognizer delegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)setEnableGestures:(BOOL)enableGestures {
    if (enableGestures != _enableGestures) {
        if (enableGestures) {
            // add gesture recognizers to KeyboardView (for typing faster)
            JTKeyboardGestureRecognizer *pan = [[JTKeyboardGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
            pan.delegate = self;
            [self.keyboardView addGestureRecognizer:pan];
            self.panGesture = pan;
        } else {
            [self.panGesture.view removeGestureRecognizer:self.panGesture];
            self.panGesture = nil;
        }
        _enableGestures = enableGestures;
    }
}

@end
