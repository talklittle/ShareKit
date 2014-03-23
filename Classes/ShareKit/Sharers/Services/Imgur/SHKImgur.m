//  Created by Andrew Shu on 03/20/2014.

//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "SHKImgur.h"

#import "NSDictionary+Recursive.h"
#import "SharersCommonHeaders.h"
#import "SHKImgurOAuthView.h"

#define kSHKImgurUserInfo @"kSHKImgurUserInfo"

@interface SHKImgur ()
@property (copy, nonatomic) NSString *accessTokenString;
@property (copy, nonatomic) NSString *refreshTokenString;
@property (copy, nonatomic) NSDate *expirationDate;

@property (copy, nonatomic) NSString *accessTokenType;
@property (copy, nonatomic) NSDate *accessTokenExpirationDate;
@property (copy, nonatomic) NSString *authorizationCode;
@end

@implementation SHKImgur


#pragma mark -
#pragma mark Configuration : Service Defination

+ (NSString *)sharerTitle
{
	return SHKLocalizedString(@"Imgur");
}


 + (BOOL)canShareURL
 {
 return YES;
 }

 + (BOOL)canShareImage
 {
 return YES;
 }

 + (BOOL)canShareFile:(SHKFile *)file
 {
 return YES;
 }

 + (BOOL)canGetUserInfo
 {
 return YES;
 }



#pragma mark -
#pragma mark Configuration : Dynamic Enable


#pragma mark -
#pragma mark Authentication

- (id)init
{
    self = [super init];
    
	if (self)
	{
		self.consumerKey = SHKCONFIG(imgurClientID);
		self.secretKey = SHKCONFIG(imgurClientSecret);
 		self.authorizeCallbackURL = [NSURL URLWithString:SHKCONFIG(imgurCallbackURL)];
		
		// -- //
		
	    self.requestURL   = nil;
	    self.authorizeURL = [NSURL URLWithString:@"https://api.imgur.com/oauth2/authorize"];
	    self.accessURL    = [NSURL URLWithString:@"https://api.imgur.com/oauth2/token"];
	}
	return self;
}

- (BOOL)isAuthorized {
    return [self restoreAccessToken];
}

- (void)tokenRequest {
    // OAuth 2.0 does not have this step.
    // Skip to Token Authorize step.
    [self tokenAuthorize];
}

- (void)tokenAuthorize
{
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@?response_type=token&client_id=%@", [self.authorizeURL absoluteString], self.consumerKey]];
	
	SHKImgurOAuthView *auth = [[SHKImgurOAuthView alloc] initWithURL:url delegate:self];
	[[SHK currentHelper] showViewController:auth];
}

- (void)tokenAuthorizeView:(SHKOAuthView *)authView didFinishWithSuccess:(BOOL)success queryParams:(NSMutableDictionary *)queryParams error:(NSError *)error {
	[[SHK currentHelper] hideCurrentViewControllerAnimated:YES];
    if (success) {
        self.accessTokenString  = [queryParams objectForKey:@"access_token"];
        self.accessTokenType    = [queryParams objectForKey:@"token_type"];
        self.refreshTokenString = [queryParams objectForKey:@"refresh_token"];
        self.expirationDate     = [NSDate dateWithTimeIntervalSinceNow:[[queryParams objectForKey:@"expires_in"] doubleValue]];
        [self storeAccessToken];
        [self tryPendingAction];
        
    } else {
        [[[UIAlertView alloc] initWithTitle:SHKLocalizedString(@"Access Error")
                                    message:error!=nil?[error localizedDescription]:SHKLocalizedString(@"There was an error while sharing")
                                   delegate:nil
                          cancelButtonTitle:SHKLocalizedString(@"Close")
                          otherButtonTitles:nil] show];
    }
    [self authDidFinish:success];
}

- (void)tokenAuthorizeCancelledView:(SHKOAuthView *)authView {
}

- (void)storeAccessToken
{
	[SHK setAuthValue:self.accessTokenString
               forKey:@"accessToken"
            forSharer:[self sharerId]];
	
	[SHK setAuthValue:self.accessTokenType
               forKey:@"accessTokenType"
            forSharer:[self sharerId]];
	
	[SHK setAuthValue:self.refreshTokenString
               forKey:@"refreshToken"
			forSharer:[self sharerId]];
	
	[SHK setAuthValue:[@([self.expirationDate timeIntervalSinceReferenceDate]) stringValue]
			   forKey:@"expirationDate"
			forSharer:[self sharerId]];
}

+ (void)deleteStoredAccessToken
{
	NSString *sharerId = [self sharerId];
	
	[SHK removeAuthValueForKey:@"accessToken" forSharer:sharerId];
	[SHK removeAuthValueForKey:@"accessTokenType" forSharer:sharerId];
	[SHK removeAuthValueForKey:@"refreshToken" forSharer:sharerId];
	[SHK removeAuthValueForKey:@"expirationDate" forSharer:sharerId];
}


//if the sharer can get user info (and it should!) override these convenience methods too. Replace example implementation with the one specific for your sharer.
+ (NSString *)username {
    
    NSDictionary *userInfo = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSHKImgurUserInfo];
    NSString *result = [userInfo findRecursivelyValueForKey:@"_content"];
    return result;
}

+ (void)logout {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSHKImgurUserInfo];
    [super logout];
}

- (BOOL)restoreAccessToken {
    NSString *sharerId = [self sharerId];
    
    self.accessTokenString  = [SHK getAuthValueForKey:@"accessToken" forSharer:sharerId];
    self.accessTokenType    = [SHK getAuthValueForKey:@"accessTokenType" forSharer:sharerId];
    self.refreshTokenString = [SHK getAuthValueForKey:@"refreshToken" forSharer:sharerId];
    self.expirationDate     = [NSDate dateWithTimeIntervalSinceReferenceDate:[[SHK getAuthValueForKey:@"expirationDate" forSharer:sharerId] doubleValue]];
    
    return self.accessTokenString && ![@"" isEqualToString:self.accessTokenString] && [self.expirationDate compare:[NSDate date]] == NSOrderedDescending;
}

#pragma mark -
#pragma mark Share Form

// If your action has options or additional information it needs to get from the user,
// use this to create the form that is presented to user upon sharing. You can even set validationBlock to validate user's input for any field setting)
/*
 - (NSArray *)shareFormFieldsForType:(SHKShareType)type
 {
 // See http://getsharekit.com/docs/#forms for documentation on creating forms
 
 if (type == SHKShareTypeURL)
 {
 // An example form that has a single text field to let the user edit the share item's title
 return [NSArray arrayWithObjects:
 [SHKFormFieldSettings label:@"Title" key:@"title" type:SHKFormFieldTypeText start:item.title],
 nil];
 }
 
 else if (type == SHKShareTypeImage)
 {
 // return a form if required when sharing an image
 return nil;
 }
 
 else if (type == SHKShareTypeText)
 {
 // return a form if required when sharing text
 return nil;
 }
 
 else if (type == SHKShareTypeFile)
 {
 // return a form if required when sharing a file
 return nil;
 }
 
 return nil;
 }
 */

// If you have a share form the user will have the option to skip it in the future.
// If your form has required information and should never be skipped, uncomment this section.
/*
 + (BOOL)canAutoShare
 {
 return NO;
 }
 */

#pragma mark -
#pragma mark Implementation

// When an attempt is made to share the item, verify that it has everything it needs, otherwise display the share form
/*
 - (BOOL)validateItem
 {
 // The super class will verify that:
 // -if sharing a url	: item.url != nil
 // -if sharing an image : item.image != nil
 // -if sharing text		: item.text != nil
 // -if sharing a file	: item.data != nil
 // -if requesting user info : return YES
 
 return [super validateItem];
 }
 */

// Send the share item to the server
- (BOOL)send
{
	if (![self validateItem])
		return NO;
	
	/*
	 Enter the necessary logic to share the item here.
	 
	 The shared item and relevant data is in self.item
	 // See http://getsharekit.com/docs/#sending
	 
	 --
	 
	 A common implementation looks like:
     
	 -  Send a request to the server
	 -  call [self sendDidStart] after you start your action
	 -  after the action completes, handle the response in didFinishSelector: or didFailSelector: methods.	 */
	
	// Here is an example.
	// This example is for a service that can share a URL
    
    // For more information on OAMutableURLRequest see http://code.google.com/p/oauthconsumer/wiki/UsingOAuthConsumer
    OAMutableURLRequest *oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"http://api.example.com/share"]
                                                                    consumer:self.consumer // this is a consumer object already made available to us
                                                                       token:self.accessToken // this is our accessToken already made available to us
                                                                       realm:nil
                                                           signatureProvider:self.signatureProvider];
    
    // Set the http method (POST or GET)
    [oRequest setHTTPMethod:@"POST"];
    
    SHKItem *item = self.item;
    
    // Determine which type of share to do
    switch (item.shareType) {
        case SHKShareTypeURL:
        {
            // Create our parameters
            OARequestParameter *urlParam = [[OARequestParameter alloc] initWithName:@"url" value:SHKEncodeURL(item.URL)];
            OARequestParameter *titleParam = [[OARequestParameter alloc] initWithName:@"title" value:SHKEncode(item.title)];
            
            // Add the params to the request
            [oRequest setParameters:[NSArray arrayWithObjects:titleParam, urlParam, nil]];
        }
        case SHKShareTypeFile:
        {
            if (self.item.URLContentType == SHKURLContentTypeImage) {
                
                // Create our parameters
                OARequestParameter *typeParam = [[OARequestParameter alloc] initWithName:@"type" value:@"photo"];
                OARequestParameter *captionParam = [[OARequestParameter alloc] initWithName:@"caption" value:item.title];
                
                //Setup the request...
                
                NSMutableArray *params = [NSMutableArray array];
                [params addObjectsFromArray:@[typeParam, captionParam]];
                
                /* bellow lines might help you upload binary data */
                
                //make OAuth signature prior appending the multipart/form-data
                [oRequest prepare];
                
                //create multipart
                [oRequest attachFileWithParameterName:@"data" filename:item.file.filename contentType:item.file.mimeType data:item.file.data];
            }
        }
        default:
            return NO;
            break;
    }
    // Start the request
    OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:oRequest
                                                                                          delegate:self
                                                                                 didFinishSelector:@selector(sendTicket:didFinishWithData:)
                                                                                   didFailSelector:@selector(sendTicket:didFailWithError:)];
    [fetcher start];
    
    // Notify delegate
    [self sendDidStart];
    
    return YES;
}

/* This is a continuation of the example provided in 'send' above.  These methods handle the OAAsynchronousDataFetcher response and should be implemented - your duty is to check the response and decide, if send finished OK, or what kind of error there is. Depending on the result, you should call one of these methods:
 
 [self sendDidFinish]; (if successful)
 [self shouldReloginWithPendingAction:SHKPendingSend]; (if credentials saved in app are obsolete - e.g. user might have changed password, or revoked app access - this will prompt for new credentials and silently share after successful login)
 [self shouldReloginWithPendingAction:SHKPendingShare]; (if credentials saved in app are obsolete - e.g. user might have changed password, or revoked app access - this will prompt for new credentials and present share UI dialogue after successful login. This can happen if the service always requires to check credentials prior send request).
 [self sendShowSimpleErrorAlert]; (in case of other error)
 [self sendDidCancel];(in case of user cancelled - you might need this if the service presents its own UI for sharing))
 */

- (void)sendTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data
{
	if (ticket.didSucceed)
	{
		// The send was successful
		[self sendDidFinish];
	}
	
	else
	{
		// Handle the error. You can scan the string created from NSData for some result code, or you can use SHKXMLResponseParser. For inspiration look at how existing sharers do this.
		
		// If the error was the result of the user no longer being authenticated, you can reprompt
		// for the login information with:
		[self shouldReloginWithPendingAction:SHKPendingSend];
		
		// Otherwise, all other errors should end with:
		[self sendShowSimpleErrorAlert];
	}
}
- (void)sendTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error
{
	[self sendShowSimpleErrorAlert];
}

@end
