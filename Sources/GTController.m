//
//  GTController.m
//  GeoTag
//
//  Created by Marco S Hyman on 6/14/09.
//

#import "GTController.h"
#import "GTDefaultscontroller.h"

@interface GTController ()
- (void) showProgressIndicator;
- (void) hideProgressIndicator;
- (NSProgressIndicator *) progressIndicator;
@end


@implementation GTController {
    IBOutlet GTTableView *tableView;
    IBOutlet NSImageView *imageWell;
    IBOutlet GTMapView *mapView;
    IBOutlet NSProgressIndicator *progressIndicator;
    
    NSMutableArray *imageInfos;
    NSUndoManager *undoManager;
}


#pragma mark -
#pragma mark Startup and teardown

- (id) init
{
    if ((self = [super init])) {
        imageInfos = [[NSMutableArray alloc] init];
        undoManager = [[NSUndoManager alloc] init];
        // force app defaults and preferences initialization
        [GTDefaultsController class];
    }
    return self;
}

- (void) awakeFromNib
{
    [NSApp setDelegate: self];
    [tableView registerForDraggedTypes: @[NSFilenamesPboardType]];
}

- (BOOL) applicationShouldTerminateAfterLastWindowClosed: (NSApplication *) sender
{
    return YES;
}

/*
 * If there are unsaved changes put up an alert sheet asking
 * what to do and return NO.   The final action will depend
 * upon what button the user selects.
 */
- (void) alertEnded: (NSAlert *) alert
           withCode: (NSInteger) choice
            context: (void *) context
{
    NSWindow *window = (__bridge_transfer NSWindow *) context;
    switch (choice) {
        case NSAlertFirstButtonReturn:
            // Save
            [self saveLocations: self];
            break;
        case NSAlertSecondButtonReturn:
            // Cancel
            return;
        default:
            // Don't save
            break;
    }
    [window setDocumentEdited: NO];
    [window close];
}

- (BOOL) saveOrDontSave: (NSWindow *) window
{
    if ([window isDocumentEdited]) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle: NSLocalizedString(@"SAVE", @"Save")];
        [alert addButtonWithTitle: NSLocalizedString(@"CANCEL", @"Cancel")];
        [alert addButtonWithTitle: NSLocalizedString(@"DONT_SAVE", @"Don't Save")];
        [alert setMessageText: NSLocalizedString(@"UNSAVED_TITLE", @"Unsaved Changes")];
        [alert setInformativeText: NSLocalizedString(@"UNSAVED_DESC", @"Unsaved Changes")];
        [alert beginSheetModalForWindow: window
                          modalDelegate: self
                         didEndSelector: @selector(alertEnded:withCode:context:)
                            contextInfo: (__bridge_retained void *) window];
        return NO;
    }
    return YES;
}

- (NSApplicationTerminateReply) applicationShouldTerminate: (NSApplication *) app
{
    if ([self saveOrDontSave: [app mainWindow]])
        return NSTerminateNow;
    return NSTerminateCancel;
}

- (BOOL) windowShouldClose: (id) window
{
    return [self saveOrDontSave: window];
}

#pragma mark -
#pragma mark image related methods

- (ImageInfo *) imageAtIndex: (NSInteger) ix
{
    return imageInfos[ix];
}

- (BOOL) isValidImageAtIndex: (NSInteger) ix
{
    if ((ix >= 0) && (ix < (NSInteger) [imageInfos count]))
        return [[self imageAtIndex: ix] validImage];
    return NO;
}

- (BOOL) addImageForPath: (NSString *) path
{
    if (! [self isDuplicatePath: path]) {
        [imageInfos addObject: [ImageInfo imageInfoWithPath: path]];
        return YES;
    }
    return NO;
}

- (BOOL) isDuplicatePath: (NSString *) path
{
    for (ImageInfo *imageInfo in imageInfos) {
        if ([[imageInfo path] isEqualToString: path])
            return YES;
    }
    return NO;
}

#pragma mark -
#pragma mark undo related methods

- (NSUndoManager *) undoManager
{
    return undoManager;
}

- (NSUndoManager *) windowWillReturnUndoManager: (NSWindow *) window
{
    return [self undoManager];
}

#pragma mark -
#pragma mark IB Actions

/*
 * open the preference window
 */
- (IBAction) showPreferencePanel: (id) sender
{
    [[GTDefaultsController sharedPrefsWindowController] showWindow:nil];
}

/*
 * Let the user select images or directories of images from an
 * open dialog box.  Don't allow duplicate paths.  Spit out a
 * notification if some files could not be opened.
 */

- (IBAction) showOpenPanel: (id) sender
{
    BOOL reloadNeeded = NO;
    BOOL showWarning = NO;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    NSArray *types =
        (__bridge_transfer NSArray *)CGImageSourceCopyTypeIdentifiers();
    [panel setAllowedFileTypes: types];
    [panel setAllowsMultipleSelection: YES];
    [panel setCanChooseFiles: YES];
    [panel setCanChooseDirectories: NO];
    NSInteger result = [panel runModal];
    if (result == NSOKButton) {
        // this may take a while, let the user know we're busy
        [self showProgressIndicator];
        NSArray *urls = [panel URLs];
        for (NSURL *url in urls) {
        NSString *path = [url path];
            if (! [self isDuplicatePath: path]) {
                [imageInfos addObject: [ImageInfo imageInfoWithPath: path]];
                reloadNeeded = YES;
            } else
                showWarning = YES;
        }
        [self hideProgressIndicator];

        if (reloadNeeded)
            [tableView reloadData];
        if (showWarning) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert addButtonWithTitle: NSLocalizedString(@"CLOSE", @"Close")];
            [alert setMessageText: NSLocalizedString(@"WARN_TITLE", @"Files not opened")];
            [alert setInformativeText: NSLocalizedString(@"WARN_DESC", @"Files not opened")];
            [alert runModal];
        }
    }
}

/*
 * Update any images that had a new location assigned.
 */
- (IBAction) saveLocations: (id) sender
{
    [self showProgressIndicator];
    dispatch_group_t dispatchGroup = dispatch_group_create();
    for (ImageInfo *imageInfo in imageInfos)
        [imageInfo saveLocationWithGroup: dispatchGroup];
    dispatch_group_wait(dispatchGroup, DISPATCH_TIME_FOREVER);
    [[NSApp mainWindow] setDocumentEdited: NO];
    // can not undo past a save
    [[self undoManager] removeAllActions];
    [self hideProgressIndicator];
}

/*
 *
 */
- (IBAction) revertToSaved: (id) sender
{
    for (ImageInfo *imageInfo in imageInfos)
        [imageInfo revertLocation];
    [[NSApp mainWindow] setDocumentEdited: NO];
    [[self undoManager] removeAllActions];
    [tableView reloadData];
    NSInteger row = [tableView selectedRow];
    if (row != -1)
        [self adjustMapViewForRow: row];
}

- (IBAction) clear: (id) sender
{
    if (! [[NSApp mainWindow] isDocumentEdited]) {
        imageInfos = [[NSMutableArray alloc] init];
        [[self undoManager] removeAllActions];
        [tableView reloadData];
    }
}

#pragma mark -
#pragma mark menu item validation

- (BOOL) validateMenuItem: (NSMenuItem *) item
{
    SEL action = [item action];
    
    if (action == @selector(saveLocations:) ||
        action == @selector(revertToSaved:))
        return [[NSApp mainWindow] isDocumentEdited];
    if (action == @selector(clear:))
        return ([imageInfos count] > 0) &&
               (! [[NSApp mainWindow] isDocumentEdited]);
    return YES;
}

#pragma mark -
#pragma mark tableView datasource and drop methods

- (NSInteger) numberOfRowsInTableView: (NSTableView *) tv
{
    return [imageInfos count];
}

- (id)            tableView: (NSTableView *) tv
  objectValueForTableColumn: (NSTableColumn *) tableColumn
                        row: (NSInteger) row
{
    ImageInfo *imageInfo = [self imageAtIndex: row];
    return [imageInfo valueForKey: [tableColumn identifier]];
}

// Drops are only allowed at the end of the table
- (NSDragOperation) tableView: (NSTableView *) aTableView
                 validateDrop: (id < NSDraggingInfo >) info
                  proposedRow: (NSInteger) row
        proposedDropOperation: (NSTableViewDropOperation) op
{
    BOOL dropValid = YES;
    
    NSPasteboard* pboard = [info draggingPasteboard];
    if ([[pboard types] containsObject: NSFilenamesPboardType]) {
        if (row < [aTableView numberOfRows])
            dropValid = NO;
        else {
            NSArray *pathArray =
                [pboard propertyListForType:NSFilenamesPboardType];
            NSFileManager *fileManager = [NSFileManager defaultManager];
            BOOL dir;
            for (NSString *path in pathArray) {
                [fileManager fileExistsAtPath: path isDirectory: &dir];
                if (dir || [self isDuplicatePath: path])
                    dropValid = NO;
            }
        }
    }
    if (dropValid)
        return NSDragOperationLink;
    
    return NSDragOperationNone;
}


- (BOOL) tableView: (NSTableView *) aTableView
        acceptDrop: (id <NSDraggingInfo>) info
               row: (NSInteger) row
     dropOperation: (NSTableViewDropOperation) op 
{
    BOOL dropAccepted = NO;
    
    NSPasteboard* pboard = [info draggingPasteboard];
    if ([[pboard types] containsObject: NSFilenamesPboardType]) {
        NSArray *pathArray = [pboard propertyListForType:NSFilenamesPboardType];
        for (NSString *path in pathArray)
            if ([self addImageForPath: path])
                dropAccepted = YES;
    }
    if (dropAccepted) {
        [tableView reloadData];
        [tableView selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
          byExtendingSelection: NO];
    }

    return dropAccepted;
} 

#pragma mark -
#pragma mark image well control


/*
 * starting with 10.6 the image will be in the proper orientation.
 */
- (void) showImageForIndex: (NSInteger) ix
{
    NSImage *image = nil;
    if (ix != -1) {
        image = [[self imageAtIndex: ix] image];
        [self adjustMapViewForRow: ix];
    }
    [imageWell setImage: image];
}

#pragma mark -
#pragma mark map view control

- (void) adjustMapViewForRow: (NSInteger) row
{
    ImageInfo * image = [self imageAtIndex: row];
    if ([image validLocation])
        [mapView adjustMapForLatitude: [image latitude]
                            longitude: [image longitude]
                                 name: [image name]];
    else
        [mapView hideMarker: @""];
}

// called from the map view when a marker is moved.
- (void) updateLatitude: (NSString *) lat
              longitude: (NSString *) lng
{
    NSIndexSet *rows = [tableView selectedRowIndexes];
    [rows enumerateIndexesUsingBlock: ^(NSUInteger row, BOOL *stop) {
        [self updateLocationForImageAtRow: row
                                 latitude: lat
                                longitude: lng
                                 modified: YES];
    }];
}

#pragma mark -
#pragma mark progress indicator control

- (NSProgressIndicator *) progressIndicator
{
    return progressIndicator;
}

- (void) showProgressIndicator
{
    NSProgressIndicator* pind = [self progressIndicator];
    [pind setUsesThreadedAnimation:YES];
    [pind setHidden:NO];
    [pind startAnimation:self];
    [pind display];
}

- (void) hideProgressIndicator
{
    NSProgressIndicator* pind = [self progressIndicator];
    [pind stopAnimation:self];
    [pind setHidden:YES];
}

#pragma mark -
#pragma mark undoable image update

// location update with undo/redo support
- (void) updateLocationForImageAtRow: (NSInteger) row
                            latitude: (NSString *) lat
                           longitude: (NSString *) lng
                            modified: (BOOL) mod
{
    NSString *curLat = NULL;
    NSString *curLng = NULL;
    ImageInfo *image = [self imageAtIndex: row];
    if ([image validLocation]) {
        curLat = [NSString stringWithFormat: @"%f", [image latitude]];
        curLng = [NSString stringWithFormat: @"%f", [image longitude]];
    }
    NSUndoManager *undo = [self undoManager];
    [[undo prepareWithInvocationTarget: self]
        updateLocationForImageAtRow: row
                           latitude: curLat
                          longitude: curLng
                           modified: [[NSApp mainWindow] isDocumentEdited]];
    [image setLocationToLatitude: lat longitude: lng];
    //  Needed with undo/redo to force mapView update
    // (mapView updated in tableViewSelectionDidChange)
    if ([undo isUndoing] || [undo isRedoing]) {
        [tableView deselectRow: row];
        [tableView selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
               byExtendingSelection: NO];
    }
    [tableView setNeedsDisplayInRect: [tableView rectOfRow: row]];
    [[NSApp mainWindow] setDocumentEdited: mod];
}

@end
