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
#import "SHKSession.h"

#define kSHKImgurUserInfo @"kSHKImgurUserInfo"

@interface SHKImgur ()
@property (copy, nonatomic) NSString *accessTokenString;
@property (copy, nonatomic) NSString *accessTokenType;
@property (copy, nonatomic) NSString *refreshTokenString;
@property (copy, nonatomic) NSDate *expirationDate;
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
    NSString *mimeType = [file mimeType];
    return [mimeType hasPrefix:@"image/"];
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
        [[self class] setUsername:[queryParams objectForKey:@"account_username"]];
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
    NSString *result = [userInfo findRecursivelyValueForKey:@"username"];
    return result;
}

+ (void)setUsername:(NSString *)username {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *userInfo = [[defaults dictionaryForKey:kSHKImgurUserInfo] mutableCopy];
    if (!userInfo) {
        userInfo = [NSMutableDictionary dictionary];
    }
    [userInfo setObject:username forKey:@"username"];
    [defaults setObject:[userInfo copy] forKey:kSHKImgurUserInfo];
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

- (BOOL)send
{
	if (![self validateItem])
		return NO;
    
    switch (self.item.shareType) {
        case SHKShareTypeImage:
        case SHKShareTypeFile:
            [self uploadPhoto];
            break;
        default:
            break;
    }
    
    [self sendDidStart];
    return YES;
}

- (OAAsynchronousDataFetcher *)uploadPhoto {

    NSMutableURLRequest *oRequest;

    BOOL canUseNSURLSession = NSClassFromString(@"NSURLSession") != nil;
    if (canUseNSURLSession) {
        oRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"https://api.imgur.com/3/upload"]];
    } else {
        // FIXME
        oRequest = [[OAMutableURLRequest alloc] initWithURL:[NSURL URLWithString:@"https://api.imgur.com/3/upload"]
                                                   consumer:self.consumer
                                                      token:self.accessToken
                                                      realm:nil
                                          signatureProvider:self.signatureProvider];
    }
    [oRequest setHTTPMethod:@"POST"];
    
    if ([self isAuthorized]) {
        // OAuth 2.0 header
        [oRequest addValue:[NSString stringWithFormat:@"Bearer %@", self.accessTokenString] forHTTPHeaderField:@"Authorization"];
    } else {
        // Imgur Client-ID header, anonymous upload
        [oRequest addValue:[NSString stringWithFormat:@"Client-ID %@", SHKCONFIG(imgurClientID)] forHTTPHeaderField:@"Authorization"];
    }
    
    NSMutableArray *params = [[NSMutableArray alloc] initWithCapacity:2];
    if ([self.item.title length] > 0) {
        [params addObject:[[OARequestParameter alloc] initWithName:@"title" value:self.item.title]];
    }
    if ([[self.item customValueForKey:@"description"] length] > 0) {
        [params addObject:[[OARequestParameter alloc] initWithName:@"description" value:[self.item customValueForKey:@"description"]]];
    }
    [oRequest setParameters:params];
    
    if (self.item.shareType == SHKShareTypeImage) {
        
        [self.item convertImageShareToFileShareOfType:SHKImageConversionTypeJPG quality:1];
    }
    
    [oRequest attachFile:self.item.file withParameterName:@"image"];
    
    if (canUseNSURLSession) {
        
        __weak typeof(self) weakSelf = self;
        self.networkSession = [SHKSession startSessionWithRequest:oRequest delegate:self completion:^(NSData *data, NSURLResponse *response, NSError *error) {
            
            if (error.code == -999) {
                [weakSelf sendDidCancel];
            } else if (error) {
                SHKLog(@"upload photo did fail with error:%@", [error description]);
                [weakSelf sendTicket:nil didFailWithError:error];
            } else {
                BOOL success = [(NSHTTPURLResponse *)response statusCode] < 400;
                [weakSelf uploadPhotoDidFinishWithData:data success:success];
            }
            [[SHK currentHelper] removeSharerReference:weakSelf];
        }];
        [[SHK currentHelper] keepSharerReference:self];
        return nil;
        
    } else {
        
        OAAsynchronousDataFetcher *fetcher = [OAAsynchronousDataFetcher asynchronousFetcherWithRequest:(OAMutableURLRequest *)oRequest
                                                                                              delegate:self
                                                                                     didFinishSelector:@selector(uploadPhotoTicket:didFinishWithData:)
                                                                                       didFailSelector:@selector(sendTicket:didFailWithError:)];
        [fetcher start];
        return fetcher;
    }
}

- (void)uploadPhotoTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data {
    
    [self uploadPhotoDidFinishWithData:data success:ticket.didSucceed];
}

- (void)uploadPhotoDidFinishWithData:(NSData *)data success:(BOOL)success {

    NSError *error;
    NSDictionary *response = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (success) {
        
        NSString *imageID = [response findRecursivelyValueForKey:@"id"];
        
        if (imageID) {
            [self sendDidFinish];
            
        } else {
            NSString *errorMessage = [response findRecursivelyValueForKey:@"error"];
            [self sendDidFailWithError:[SHK error:errorMessage]];
        }

    } else {
        
        [self sendShowSimpleErrorAlert];
        SHKLog(@"Imgur upload failed with error:%@", [response findRecursivelyValueForKey:@"error"]);
    }
}

- (void)sendTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data
{
	if (ticket.didSucceed)
	{
		NSError *error = nil;
        NSMutableDictionary *response = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
        
        if ([response findRecursivelyValueForKey:@"_content"]) {
            
            //save userInfo
            [[NSUserDefaults standardUserDefaults] setObject:response forKey:kSHKImgurUserInfo];
            [self sendDidFinish];
            
        } else if ([response findRecursivelyValueForKey:@"group"]) {
            
            [self hideActivityIndicator];
            
            //fill in OptionController with user's groups
            NSArray *groups = [response findRecursivelyValueForKey:@"group"];
            
            if ([groups count] > 0) {
                NSMutableArray *displayGroups = [[NSMutableArray alloc] initWithCapacity:[groups count]];
                NSMutableArray *saveGroups = [[NSMutableArray alloc] initWithCapacity:[groups count]];
                for (NSDictionary *group in groups) {
                    [displayGroups addObject:group[@"name"]];
                    [saveGroups addObject:group[@"nsid"]];
                }
                [self.curOptionController optionsEnumeratedDisplay:displayGroups save:saveGroups];
            } else {
                [self.curOptionController optionsEnumerationFailedWithError:nil];
            }
        } else if ([response findRecursivelyValueForKey:@"stat"]) {
            //moved (or not, nevermind) uploaded photo to specified group
        } else {
            
            //error
//            if ([response[@"code"] integerValue] == [USER_REMOVED_ACCESS_CODE integerValue]) {
//                [self shouldReloginWithPendingAction:SHKPendingShare];
//            } else {
//                [self sendShowSimpleErrorAlert];
//            }
            SHKLog(@"flickr got error%@", [response description]);
        }
	}
	
	else
	{
		[self sendShowSimpleErrorAlert];
        NSError *error __attribute__((unused)) = nil;
        SHKLog(@"Flickr ticket did not succeed with error:%@",  [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error] description]);
        
	}
}
- (void)sendTicket:(OAServiceTicket *)ticket didFailWithError:(NSError*)error
{
	if (self.curOptionController) {
        [self.curOptionController optionsEnumerationFailedWithError:error];
    } else {
        [self sendShowSimpleErrorAlert];
    }
}

@end
