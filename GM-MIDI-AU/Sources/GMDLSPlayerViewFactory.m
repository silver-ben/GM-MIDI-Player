#import <AppKit/AppKit.h>
#import <AudioToolbox/AUCocoaUIView.h>
#import <AudioToolbox/AudioToolbox.h>

#import "GMDLSShared.h"

static NSInteger GMDLSClampProgram(NSInteger value) {
    if (value < 0) {
        return 0;
    }
    if (value > 127) {
        return 127;
    }
    return value;
}

static NSInteger GMDLSClampInstrumentControlMode(NSInteger value) {
    if (value <= 0) {
        return 0;
    }
    return 1;
}

static NSColor *GMDLSColorBackgroundApp(void) {
    return [NSColor colorWithSRGBRed:18.0 / 255.0 green:20.0 / 255.0 blue:28.0 / 255.0 alpha:1.0];
}

static NSColor *GMDLSColorBackgroundPanel(void) {
    return [NSColor colorWithSRGBRed:34.0 / 255.0 green:36.0 / 255.0 blue:46.0 / 255.0 alpha:1.0];
}

static NSColor *GMDLSColorBackgroundField(void) {
    return [NSColor colorWithSRGBRed:26.0 / 255.0 green:28.0 / 255.0 blue:36.0 / 255.0 alpha:1.0];
}

static NSColor *GMDLSColorBackgroundButton(void) {
    return [NSColor colorWithSRGBRed:49.0 / 255.0 green:51.0 / 255.0 blue:61.0 / 255.0 alpha:1.0];
}

static NSColor *GMDLSColorAccentBlue(void) {
    return [NSColor colorWithSRGBRed:40.0 / 255.0 green:85.0 / 255.0 blue:153.0 / 255.0 alpha:1.0];
}

static NSColor *GMDLSColorAccentGold(void) {
    return [NSColor colorWithSRGBRed:240.0 / 255.0 green:200.0 / 255.0 blue:46.0 / 255.0 alpha:1.0];
}

static NSColor *GMDLSColorPrimaryText(void) {
    return [NSColor colorWithWhite:0.95 alpha:1.0];
}

static NSColor *GMDLSColorSecondaryText(void) {
    return [NSColor colorWithWhite:0.74 alpha:1.0];
}

static NSTextField *GMDLSMakeLabel(CGFloat size, NSFontWeight weight, NSColor *color, NSTextAlignment alignment) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSZeroRect];
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.textColor = color;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.alignment = alignment;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

static void GMDLSStylePanel(NSView *view, NSColor *backgroundColor) {
    view.wantsLayer = YES;
    view.layer.backgroundColor = backgroundColor.CGColor;
    view.layer.borderColor = GMDLSColorBackgroundApp().CGColor;
    view.layer.borderWidth = 1.0;
}

static void GMDLSStyleReadout(NSTextField *field, NSTextAlignment alignment) {
    field.editable = NO;
    field.selectable = NO;
    field.bezeled = NO;
    field.bordered = NO;
    field.drawsBackground = YES;
    field.backgroundColor = GMDLSColorBackgroundField();
    field.textColor = GMDLSColorPrimaryText();
    field.alignment = alignment;
    field.font = [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightSemibold];
    field.focusRingType = NSFocusRingTypeNone;
    field.wantsLayer = YES;
    field.layer.borderColor = [GMDLSColorSecondaryText() colorWithAlphaComponent:0.3].CGColor;
    field.layer.borderWidth = 1.0;
}

@interface GMDLSVerticallyCenteredTextFieldCell : NSTextFieldCell
@end

@implementation GMDLSVerticallyCenteredTextFieldCell

- (CGFloat)gmdlsLineHeight {
    NSFont *font = self.font;
    if (font == nil) {
        font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    }
    CGFloat lineHeight = ceil(font.ascender - font.descender + font.leading);
    return MAX(1.0, lineHeight);
}

- (NSRect)gmdlsCenteredRectForBounds:(NSRect)bounds {
    NSRect textRect = [super drawingRectForBounds:bounds];
    CGFloat lineHeight = [self gmdlsLineHeight];
    textRect.size.height = MIN(NSHeight(bounds), lineHeight);
    textRect.origin.y = bounds.origin.y + floor((NSHeight(bounds) - NSHeight(textRect)) * 0.5);
    return NSIntegralRect(textRect);
}

- (NSRect)drawingRectForBounds:(NSRect)bounds {
    return [self gmdlsCenteredRectForBounds:bounds];
}

- (NSRect)titleRectForBounds:(NSRect)bounds {
    return [self gmdlsCenteredRectForBounds:bounds];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    [super drawInteriorWithFrame:[self gmdlsCenteredRectForBounds:cellFrame] inView:controlView];
}

- (void)editWithFrame:(NSRect)rect
               inView:(NSView *)controlView
               editor:(NSText *)textObject
             delegate:(id)delegate
                event:(NSEvent *)event {
    [super editWithFrame:[self gmdlsCenteredRectForBounds:rect]
                  inView:controlView
                  editor:textObject
                delegate:delegate
                   event:event];
}

- (void)selectWithFrame:(NSRect)rect
                 inView:(NSView *)controlView
                 editor:(NSText *)textObject
               delegate:(id)delegate
                  start:(NSInteger)selectionStart
                 length:(NSInteger)selectionLength {
    [super selectWithFrame:[self gmdlsCenteredRectForBounds:rect]
                    inView:controlView
                    editor:textObject
                  delegate:delegate
                     start:selectionStart
                    length:selectionLength];
}

@end

@interface GMDLSCenteredTextField : NSTextField
@end

@implementation GMDLSCenteredTextField
+ (Class)cellClass {
    return [GMDLSVerticallyCenteredTextFieldCell class];
}
@end

@interface GMDLSFlippedView : NSView
@end

@implementation GMDLSFlippedView
- (BOOL)isFlipped {
    return YES;
}
@end

@interface GMDLSProgramCellView : NSControl
@property (nonatomic) NSInteger program;
@property (nonatomic, copy) NSString *programName;
@property (nonatomic) BOOL selectedProgram;
@end

@implementation GMDLSProgramCellView {
    BOOL _pressed;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self == nil) {
        return nil;
    }

    self.wantsLayer = YES;
    self.layer.masksToBounds = YES;
    self.program = 0;
    self.programName = @"Program";
    self.selectedProgram = NO;
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setProgram:(NSInteger)program {
    if (_program == program) {
        return;
    }
    _program = GMDLSClampProgram(program);
    [self setNeedsDisplay:YES];
}

- (void)setProgramName:(NSString *)programName {
    NSString *safeName = programName ?: @"Program";
    if ([_programName isEqualToString:safeName]) {
        return;
    }
    _programName = [safeName copy];
    [self setNeedsDisplay:YES];
}

- (void)setSelectedProgram:(BOOL)selectedProgram {
    if (_selectedProgram == selectedProgram) {
        return;
    }
    _selectedProgram = selectedProgram;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = NSInsetRect(self.bounds, 0.5, 0.5);
    BOOL selected = self.selectedProgram;

    NSColor *background = selected ? [GMDLSColorAccentBlue() colorWithAlphaComponent:0.7]
                                   : (_pressed ? GMDLSColorBackgroundButton() : GMDLSColorBackgroundField());
    NSColor *border = selected ? GMDLSColorAccentGold()
                               : [GMDLSColorSecondaryText() colorWithAlphaComponent:0.25];

    NSBezierPath *path = [NSBezierPath bezierPathWithRect:bounds];
    [background setFill];
    [path fill];
    path.lineWidth = selected ? 1.4 : 1.0;
    [border setStroke];
    [path stroke];

    NSString *numberText = [NSString stringWithFormat:@"%03ld", (long)self.program];
    NSDictionary *numberAttrs = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: selected ? GMDLSColorAccentGold() : GMDLSColorSecondaryText()
    };

    NSMutableParagraphStyle *nameParagraph = [[NSMutableParagraphStyle alloc] init];
    nameParagraph.alignment = NSTextAlignmentLeft;
    nameParagraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *nameAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: GMDLSColorPrimaryText(),
        NSParagraphStyleAttributeName: nameParagraph
    };

    NSRect textBounds = NSInsetRect(bounds, 8.0, 6.0);
    [numberText drawInRect:NSMakeRect(textBounds.origin.x,
                                      textBounds.origin.y,
                                      36.0,
                                      textBounds.size.height)
            withAttributes:numberAttrs];

    [self.programName drawInRect:NSMakeRect(textBounds.origin.x + 40.0,
                                            textBounds.origin.y,
                                            MAX(0.0, textBounds.size.width - 40.0),
                                            textBounds.size.height)
                  withAttributes:nameAttrs];
}

- (void)mouseDown:(NSEvent *)event {
    _pressed = YES;
    [self setNeedsDisplay:YES];

    BOOL tracking = YES;
    while (tracking) {
        NSEvent *nextEvent = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        switch (nextEvent.type) {
            case NSEventTypeLeftMouseDragged: {
                NSPoint localPoint = [self convertPoint:nextEvent.locationInWindow fromView:nil];
                BOOL isInside = NSPointInRect(localPoint, self.bounds);
                if (_pressed != isInside) {
                    _pressed = isInside;
                    [self setNeedsDisplay:YES];
                }
                break;
            }

            case NSEventTypeLeftMouseUp: {
                NSPoint localPoint = [self convertPoint:nextEvent.locationInWindow fromView:nil];
                BOOL isInside = NSPointInRect(localPoint, self.bounds);
                if (isInside) {
                    [self sendAction:self.action to:self.target];
                }
                tracking = NO;
                break;
            }

            default:
                break;
        }
    }

    _pressed = NO;
    [self setNeedsDisplay:YES];
}

@end

@interface GMDLSProgramBrowserView : NSView <NSTextFieldDelegate>
- (instancetype)initWithAudioUnit:(AudioUnit)audioUnit frame:(NSRect)frame;
@end

@implementation GMDLSProgramBrowserView {
    AudioUnit _audioUnit;
    NSArray<NSString *> *_programNames;
    NSMutableArray<NSNumber *> *_filteredPrograms;
    NSMutableArray<GMDLSProgramCellView *> *_programCells;
    NSInteger _currentProgram;
    NSInteger _instrumentControlMode;
    BOOL _updatingSelection;

    GMDLSFlippedView *_panel;
    NSTextField *_titleLabel;
    NSTextField *_subtitleLabel;
    NSTextField *_currentProgramField;
    NSTextField *_currentNameLabel;
    NSTextField *_modeLabel;
    NSSegmentedControl *_modeControl;
    NSTextField *_searchLabel;
    NSTextField *_searchField;
    NSScrollView *_scrollView;
    GMDLSFlippedView *_gridView;
    NSTextField *_emptyLabel;
    NSTextField *_creditLabel;
    NSTimer *_syncTimer;
}

- (instancetype)initWithAudioUnit:(AudioUnit)audioUnit frame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }

    _audioUnit = audioUnit;
    _currentProgram = 0;
    _instrumentControlMode = 0;
    _programNames = CFBridgingRelease(GMDLSCopyGMProgramNames());
    if (_programNames.count != 128) {
        _programNames = @[];
    }

    _filteredPrograms = [[NSMutableArray alloc] initWithCapacity:_programNames.count];
    _programCells = [[NSMutableArray alloc] initWithCapacity:_programNames.count];

    self.wantsLayer = YES;
    self.layer.backgroundColor = GMDLSColorBackgroundApp().CGColor;

    _panel = [[GMDLSFlippedView alloc] initWithFrame:NSZeroRect];
    GMDLSStylePanel(_panel, GMDLSColorBackgroundPanel());
    [self addSubview:_panel];

    _titleLabel = GMDLSMakeLabel(19.0, NSFontWeightSemibold, GMDLSColorPrimaryText(), NSTextAlignmentLeft);
    _titleLabel.stringValue = @"GM DLS Player";
    [_panel addSubview:_titleLabel];

    _subtitleLabel = GMDLSMakeLabel(11.0, NSFontWeightRegular, GMDLSColorSecondaryText(), NSTextAlignmentLeft);
    _subtitleLabel.stringValue = @"General MIDI patch browser";
    [_panel addSubview:_subtitleLabel];

    _currentProgramField = [[GMDLSCenteredTextField alloc] initWithFrame:NSZeroRect];
    GMDLSStyleReadout(_currentProgramField, NSTextAlignmentCenter);
    [_panel addSubview:_currentProgramField];

    _currentNameLabel = GMDLSMakeLabel(12.0, NSFontWeightMedium, GMDLSColorPrimaryText(), NSTextAlignmentRight);
    [_panel addSubview:_currentNameLabel];

    _modeLabel = GMDLSMakeLabel(10.0, NSFontWeightSemibold, GMDLSColorSecondaryText(), NSTextAlignmentLeft);
    _modeLabel.stringValue = @"INSTRUMENT SOURCE";
    [_panel addSubview:_modeLabel];

    _modeControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    [_modeControl setSegmentCount:2];
    [_modeControl setLabel:@"Host MIDI" forSegment:0];
    [_modeControl setLabel:@"Plugin UI" forSegment:1];
    _modeControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
    _modeControl.target = self;
    _modeControl.action = @selector(modeControlChanged:);
    _modeControl.selectedSegment = 0;
    [_panel addSubview:_modeControl];

    _searchLabel = GMDLSMakeLabel(10.0, NSFontWeightSemibold, GMDLSColorSecondaryText(), NSTextAlignmentLeft);
    _searchLabel.stringValue = @"SEARCH";
    [_panel addSubview:_searchLabel];

    _searchField = [[GMDLSCenteredTextField alloc] initWithFrame:NSZeroRect];
    _searchField.delegate = self;
    _searchField.bordered = NO;
    _searchField.bezeled = NO;
    _searchField.drawsBackground = YES;
    _searchField.backgroundColor = GMDLSColorBackgroundField();
    _searchField.textColor = GMDLSColorPrimaryText();
    _searchField.focusRingType = NSFocusRingTypeNone;
    _searchField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    _searchField.placeholderAttributedString = [[NSAttributedString alloc]
        initWithString:@"Type program number or instrument name"
            attributes:@{
                NSFontAttributeName: _searchField.font,
                NSForegroundColorAttributeName: [GMDLSColorSecondaryText() colorWithAlphaComponent:0.72]
            }];
    _searchField.wantsLayer = YES;
    _searchField.layer.borderColor = [GMDLSColorSecondaryText() colorWithAlphaComponent:0.32].CGColor;
    _searchField.layer.borderWidth = 1.0;
    [_panel addSubview:_searchField];

    _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.scrollerStyle = NSScrollerStyleOverlay;
    _scrollView.autohidesScrollers = YES;
    _scrollView.wantsLayer = YES;
    _scrollView.layer.borderColor = [GMDLSColorSecondaryText() colorWithAlphaComponent:0.22].CGColor;
    _scrollView.layer.borderWidth = 1.0;
    [_panel addSubview:_scrollView];

    _gridView = [[GMDLSFlippedView alloc] initWithFrame:NSZeroRect];
    _gridView.wantsLayer = YES;
    _gridView.layer.backgroundColor = GMDLSColorBackgroundApp().CGColor;
    _scrollView.documentView = _gridView;

    _emptyLabel = GMDLSMakeLabel(13.0, NSFontWeightMedium, GMDLSColorSecondaryText(), NSTextAlignmentCenter);
    _emptyLabel.stringValue = @"No matching instruments";
    _emptyLabel.hidden = YES;
    [_gridView addSubview:_emptyLabel];

    _creditLabel = GMDLSMakeLabel(10.0, NSFontWeightRegular, [GMDLSColorSecondaryText() colorWithAlphaComponent:0.85], NSTextAlignmentLeft);
    _creditLabel.stringValue = @"Developed by Ben Silver";
    [_panel addSubview:_creditLabel];

    [self rebuildFilteredPrograms];
    [self rebuildGrid];
    [self updateCurrentProgramUI];
    [self syncFromAudioUnit];

    _syncTimer = [NSTimer scheduledTimerWithTimeInterval:0.15
                                                  target:self
                                                selector:@selector(syncFromAudioUnit)
                                                userInfo:nil
                                                 repeats:YES];

    return self;
}

- (void)dealloc {
    [_syncTimer invalidate];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)layout {
    [super layout];

    const CGFloat outerPadding = 12.0;
    const CGFloat panelPadding = 12.0;
    const CGFloat sectionGap = 10.0;

    _panel.frame = NSInsetRect(self.bounds, outerPadding, outerPadding);
    NSRect inner = NSInsetRect(_panel.bounds, panelPadding, panelPadding);

    CGFloat y = inner.origin.y;

    _titleLabel.frame = NSMakeRect(inner.origin.x,
                                   y,
                                   MAX(160.0, inner.size.width * 0.45),
                                   24.0);

    _currentProgramField.frame = NSMakeRect(NSMaxX(inner) - 118.0,
                                            y + 1.0,
                                            118.0,
                                            22.0);
    y += 24.0;

    _subtitleLabel.frame = NSMakeRect(inner.origin.x,
                                      y,
                                      MAX(160.0, inner.size.width * 0.45),
                                      16.0);

    _currentNameLabel.frame = NSMakeRect(NSMaxX(inner) - 360.0,
                                         y,
                                         360.0,
                                         16.0);
    y += 22.0;

    _modeLabel.frame = NSMakeRect(inner.origin.x,
                                  y,
                                  130.0,
                                  14.0);
    CGFloat modeControlWidth = MIN(300.0, MAX(180.0, inner.size.width - 138.0));
    _modeControl.frame = NSMakeRect(inner.origin.x + 138.0,
                                    y - 3.0,
                                    modeControlWidth,
                                    22.0);
    y += 24.0;

    _searchLabel.frame = NSMakeRect(inner.origin.x,
                                    y,
                                    60.0,
                                    14.0);
    y += 16.0;

    _searchField.frame = NSMakeRect(inner.origin.x,
                                    y,
                                    inner.size.width,
                                    26.0);
    y += 26.0 + sectionGap;

    const CGFloat footerHeight = 12.0;
    const CGFloat footerGap = 8.0;
    CGFloat scrollHeight = MAX(120.0, NSMaxY(inner) - y - footerGap - footerHeight);
    _scrollView.frame = NSMakeRect(inner.origin.x,
                                   y,
                                   inner.size.width,
                                   scrollHeight);

    _creditLabel.frame = NSMakeRect(inner.origin.x,
                                    NSMaxY(inner) - footerHeight,
                                    MAX(200.0, inner.size.width * 0.5),
                                    footerHeight);

    [self layoutGridCells];
}

- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _searchField) {
        [self rebuildFilteredPrograms];
        [self rebuildGrid];
    }
}

- (void)rebuildFilteredPrograms {
    [_filteredPrograms removeAllObjects];

    NSString *query = [_searchField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *needle = query.lowercaseString;
    BOOL hasQuery = (needle.length > 0);

    for (NSInteger program = 0; program < (NSInteger)_programNames.count; ++program) {
        if (!hasQuery) {
            [_filteredPrograms addObject:@(program)];
            continue;
        }

        NSString *name = _programNames[(NSUInteger)program].lowercaseString;
        NSString *threeDigit = [NSString stringWithFormat:@"%03ld", (long)program];
        NSString *plainDigit = [NSString stringWithFormat:@"%ld", (long)program];

        if ([name containsString:needle] || [threeDigit containsString:needle] || [plainDigit containsString:needle]) {
            [_filteredPrograms addObject:@(program)];
        }
    }

}

- (void)rebuildGrid {
    for (GMDLSProgramCellView *cell in _programCells) {
        [cell removeFromSuperview];
    }
    [_programCells removeAllObjects];

    for (NSNumber *programNumber in _filteredPrograms) {
        NSInteger program = programNumber.integerValue;
        GMDLSProgramCellView *cell = [[GMDLSProgramCellView alloc] initWithFrame:NSZeroRect];
        cell.program = program;
        cell.programName = _programNames[(NSUInteger)program];
        cell.selectedProgram = (program == _currentProgram);
        cell.target = self;
        cell.action = @selector(programCellPressed:);
        [_gridView addSubview:cell];
        [_programCells addObject:cell];
    }

    _emptyLabel.hidden = (_programCells.count > 0);
    [self layoutGridCells];
    [self updateCurrentProgramUI];
}

- (void)layoutGridCells {
    CGFloat viewWidth = NSWidth(_scrollView.contentView.bounds);
    if (viewWidth <= 0.0) {
        viewWidth = NSWidth(_scrollView.bounds);
    }
    viewWidth = MAX(360.0, viewWidth);

    const CGFloat horizontalInset = 8.0;
    const CGFloat horizontalGap = 8.0;
    const CGFloat verticalInset = 8.0;
    const CGFloat verticalGap = 6.0;
    const CGFloat minCellWidth = 176.0;
    const CGFloat cellHeight = 28.0;

    CGFloat available = MAX(200.0, viewWidth - (horizontalInset * 2.0));
    NSInteger columns = (NSInteger)floor((available + horizontalGap) / (minCellWidth + horizontalGap));
    columns = MAX(3, columns);
    columns = MIN(5, columns);

    CGFloat totalGap = (columns - 1) * horizontalGap;
    CGFloat cellWidth = floor((available - totalGap) / columns);

    NSInteger itemCount = (NSInteger)_programCells.count;
    for (NSInteger index = 0; index < itemCount; ++index) {
        NSInteger row = index / columns;
        NSInteger column = index % columns;
        CGFloat x = horizontalInset + (column * (cellWidth + horizontalGap));
        CGFloat y = verticalInset + (row * (cellHeight + verticalGap));
        _programCells[(NSUInteger)index].frame = NSMakeRect(x, y, cellWidth, cellHeight);
    }

    NSInteger rows = (itemCount + columns - 1) / columns;
    CGFloat contentHeight = verticalInset * 2.0;
    if (rows > 0) {
        contentHeight += (rows * cellHeight) + ((rows - 1) * verticalGap);
    } else {
        contentHeight = MAX(120.0, NSHeight(_scrollView.contentView.bounds));
    }

    CGFloat minHeight = NSHeight(_scrollView.contentView.bounds);
    _gridView.frame = NSMakeRect(0.0, 0.0, viewWidth, MAX(minHeight, contentHeight));
    _emptyLabel.frame = NSMakeRect(20.0,
                                   MAX(24.0, (NSHeight(_gridView.bounds) * 0.5) - 10.0),
                                   MAX(100.0, NSWidth(_gridView.bounds) - 40.0),
                                   20.0);
}

- (void)programCellPressed:(GMDLSProgramCellView *)sender {
    [self setProgram:sender.program pushToAudioUnit:YES];
    [self scrollCurrentProgramIntoView];
}

- (void)modeControlChanged:(NSSegmentedControl *)sender {
    [self setInstrumentControlMode:sender.selectedSegment pushToAudioUnit:YES];
}

- (void)setProgram:(NSInteger)program pushToAudioUnit:(BOOL)push {
    NSInteger clamped = GMDLSClampProgram(program);
    BOOL changed = (_currentProgram != clamped);
    _currentProgram = clamped;

    [self updateCurrentProgramUI];

    if (!push || !changed || _audioUnit == NULL || _updatingSelection) {
        return;
    }

    AudioUnitSetParameter(_audioUnit,
                          kGMDLSProgramParameterID,
                          kAudioUnitScope_Global,
                          0,
                          (AudioUnitParameterValue)clamped,
                          0);
}

- (void)setInstrumentControlMode:(NSInteger)mode pushToAudioUnit:(BOOL)push {
    NSInteger clamped = GMDLSClampInstrumentControlMode(mode);
    BOOL changed = (_instrumentControlMode != clamped);
    _instrumentControlMode = clamped;

    [self updateInstrumentControlUI];

    if (!push || !changed || _audioUnit == NULL || _updatingSelection) {
        return;
    }

    AudioUnitSetParameter(_audioUnit,
                          kGMDLSInstrumentControlModeParameterID,
                          kAudioUnitScope_Global,
                          0,
                          (AudioUnitParameterValue)clamped,
                          0);
}

- (void)updateCurrentProgramUI {
    _currentProgramField.stringValue = [NSString stringWithFormat:@"PROGRAM %03ld", (long)_currentProgram];

    NSString *name = @"Program";
    if (_currentProgram >= 0 && _currentProgram < (NSInteger)_programNames.count) {
        name = _programNames[(NSUInteger)_currentProgram];
    }
    _currentNameLabel.stringValue = name;

    for (GMDLSProgramCellView *cell in _programCells) {
        cell.selectedProgram = (cell.program == _currentProgram);
    }
}

- (void)updateInstrumentControlUI {
    _modeControl.selectedSegment = _instrumentControlMode;
}

- (void)scrollCurrentProgramIntoView {
    for (GMDLSProgramCellView *cell in _programCells) {
        if (cell.program == _currentProgram) {
            [_gridView scrollRectToVisible:NSInsetRect(cell.frame, 0.0, -4.0)];
            break;
        }
    }
}

- (void)syncFromAudioUnit {
    if (_audioUnit == NULL) {
        return;
    }

    AudioUnitParameterValue programValue = 0;
    AudioUnitParameterValue modeValue = 0;
    BOOL gotProgram = (AudioUnitGetParameter(_audioUnit,
                                             kGMDLSProgramParameterID,
                                             kAudioUnitScope_Global,
                                             0,
                                             &programValue) == noErr);
    BOOL gotMode = (AudioUnitGetParameter(_audioUnit,
                                          kGMDLSInstrumentControlModeParameterID,
                                          kAudioUnitScope_Global,
                                          0,
                                          &modeValue) == noErr);
    if (!gotProgram && !gotMode) {
        return;
    }

    NSInteger clampedProgram = GMDLSClampProgram((NSInteger)llround(programValue));
    NSInteger clampedMode = GMDLSClampInstrumentControlMode((NSInteger)llround(modeValue));
    BOOL programChanged = gotProgram && (_currentProgram != clampedProgram);
    BOOL modeChanged = gotMode && (_instrumentControlMode != clampedMode);
    if (!programChanged && !modeChanged) {
        return;
    }

    _updatingSelection = YES;
    if (programChanged) {
        [self setProgram:clampedProgram pushToAudioUnit:NO];
    }
    if (modeChanged) {
        [self setInstrumentControlMode:clampedMode pushToAudioUnit:NO];
    }
    _updatingSelection = NO;
}

@end

@interface GMDLSPlayerViewFactory : NSObject <AUCocoaUIBase>
@end

@implementation GMDLSPlayerViewFactory

- (unsigned)interfaceVersion {
    return 0;
}

- (NSString *)description {
    return @"GM DLS Player";
}

- (NSView *)uiViewForAudioUnit:(AudioUnit)inAudioUnit withSize:(NSSize)inPreferredSize {
    NSSize size = inPreferredSize;
    size.width = MAX(size.width, 760.0);
    size.height = MAX(size.height, 520.0);

    return [[GMDLSProgramBrowserView alloc] initWithAudioUnit:inAudioUnit
                                                         frame:NSMakeRect(0.0, 0.0, size.width, size.height)];
}

@end
