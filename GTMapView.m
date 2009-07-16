//
//  GTMapView.m
//  GeoTag
//
//  Created by Marco S Hyman on 7/16/09.
//

#import "GTMapView.h"
#import "GTController.h"

#if GTDEBUG == 0
#define NSLog(...)
#endif

@implementation GTMapView

@synthesize appController;
@synthesize mapLat;
@synthesize mapLng;

#pragma mark -
#pragma mark WebScripting Protocol methods

// only the report selector can be called from the script
+ (BOOL) isSelectorExcludedFromWebScript: (SEL) selector
{
    NSLog(@"%@ received %@", self, NSStringFromSelector(_cmd));
    if (selector == @selector(reportPosition))
	return NO;
    return YES;
}

// the script has access to mapLat and mapLng variables
+ (BOOL) isKeyExcludedFromWebScript: (const char *) property
{
    NSLog(@"%@ received %@ for property %s", self, NSStringFromSelector(_cmd),
	  property);
    if ((strcmp(property, "mapLat") == 0) ||
	(strcmp(property, "mapLng") == 0))
        return NO;
    return YES;
    
}

// no script-to-selector name translation needed
+ (NSString *) webScriptNameForSelector: (SEL) sel
{
    NSLog(@"%@ received %@", self, NSStringFromSelector(_cmd));
    return nil;
}


#pragma mark -
#pragma mark script communication methods

// hide any existing marker
- (void) hideMarker
{
    NSLog(@"%@ received %@", self, NSStringFromSelector(_cmd));
    [[self windowScriptObject] callWebScriptMethod: @"hideMarker"
				     withArguments: nil];
}

// tell the map to hide or drop a marker
- (void) adjustMapForLatitude: (NSString *) lat
		    longitude: (NSString *) lng
			 name: (NSString *) name;
{
    NSLog(@"%@ received %@", self, NSStringFromSelector(_cmd));
    if (lat && lng) {
	NSArray* args = [NSArray arrayWithObjects: lat, lng, name, nil];
	[[self windowScriptObject] callWebScriptMethod: @"addMarkerToMapAt"
					 withArguments: args];
    } else
	[self hideMarker];
}

// called from javascript when a marker is placed on the map.
// The marker is at mapLat, mapLng.
- (void) reportPosition
{
    NSLog(@"%@ received %@", self, NSStringFromSelector(_cmd));
    [appController updateLatitude: [self mapLat] longitude: [self mapLng]];
}

#pragma mark -
#pragma mark Load initial map

- (void) loadMap
{
    [self setFrameLoadDelegate: self];
    [[self mainFrame] loadRequest:
     [NSURLRequest requestWithURL:
      [NSURL fileURLWithPath:
	[[NSBundle mainBundle] pathForResource:@"map" ofType:@"html"]]]];
}

#pragma mark -
#pragma mark WebView frame load delegate method

- (void)       webView: (WebView *) sender
  didClearWindowObject: (WebScriptObject *) windowObject
	      forFrame: (WebFrame *) frame
{
    NSLog(@"%@ received %@", self, NSStringFromSelector(_cmd));
    // javascript will know this object as "controller".
    [windowObject setValue: self forKey: @"controller"];
}


@end