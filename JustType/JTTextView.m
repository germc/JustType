//
//  JTTextView.m
//  JustType
//
//  Created by Andrea Koglin on 27.12.13.
//  Copyright (c) 2013 __MyCompanyName__. All rights reserved.
//

#import "JTTextView.h"
#import "JTTextViewMediatorDelegate.h"

@interface JTTextView ()

@property (nonatomic, retain) JTTextController *textController;
@property (nonatomic, retain) UITapGestureRecognizer *tapGesture;
@property (nonatomic, retain) UILongPressGestureRecognizer *pressGesture;

@property (nonatomic, assign) id<UITextViewDelegate> actualDelegate;
@property (nonatomic, retain) JTTextViewMediatorDelegate *mediatorDelegate;


@end


@implementation JTTextView
@synthesize textController = _textController;
@synthesize tapGesture = _tapGesture;
@synthesize pressGesture = _pressGesture;

@synthesize actualDelegate = _actualDelegate;
@synthesize mediatorDelegate = _mediatorDelegate;

#pragma mark - Object lifecycle
- (id)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.autocorrectionType = UITextAutocorrectionTypeNo;
        
        _textController = [[JTTextController alloc] init];
        _textController.delegate = self;
        
        _mediatorDelegate = [[JTTextViewMediatorDelegate alloc] init];
        _mediatorDelegate.textView = self;
    }
    return self;
}

- (void)dealloc {
    _mediatorDelegate = nil;
    _textController.delegate = nil;
    _textController = nil;
}

#pragma mark - text controller delegate actions
- (NSString *)textContent {
    return self.text;
}

- (void)highlightWord:(BOOL)shouldBeHighlighted inRange:(NSRange)range {
}


#pragma mark - Actions forwarded to controller
- (void)didChangeText {
    [self.textController didChangeText];
}

- (void)didChangeSelection {
    [self.textController didChangeSelection];
}

#pragma mark - overwritten methods
- (id<UITextViewDelegate>)delegate {
    return self.mediatorDelegate;
}

- (void)setDelegate:(id<UITextViewDelegate>)delegate {
    self.actualDelegate = delegate;
}

@end

