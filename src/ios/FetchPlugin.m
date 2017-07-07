#import "FetchPlugin.h"
#import "BaseClient.h"
#import "AFNetworkActivityLogger.h"
#include "iconv.h"


@interface FetchPlugin()

@end


@implementation FetchPlugin

- (void)pluginInitialize {
  
  [[AFNetworkActivityLogger sharedLogger] startLogging];
}

- (NSData *)cleanUTF8:(NSData *)data {
    // Make sure its utf-8
    iconv_t ic= iconv_open("UTF-8", "UTF-8");
    // Remove invaild characters
    int one = 1;
    iconvctl(ic, ICONV_SET_DISCARD_ILSEQ, &one);
    
    size_t inBytes, outBytes;
    inBytes = outBytes = data.length;
    char *inbuf  = (char*)data.bytes;
    char *outbuf = (char*) malloc(sizeof(char) * data.length);
    char *outptr = outbuf;
    
    if (iconv(ic, &inbuf, &inBytes, &outptr, &outBytes) == (size_t) - 1) {
        assert(false);
        return nil;
    }
    
    NSData *result = [NSData dataWithBytes:outbuf length:data.length - outBytes];
    iconv_close(ic);
    free(outbuf);
    return result;
}

- (void)fetch:(CDVInvokedUrlCommand *)command {
  NSString *method = [command.arguments objectAtIndex:0];
  NSString *urlString = [command.arguments objectAtIndex:1];
  id body = [command.arguments objectAtIndex:2];
  id headers = [command.arguments objectAtIndex:3];
  
  if (![body isKindOfClass:[NSString class]]) {
    body = nil;
  }
  
  if (headers[@"map"] != nil && [headers[@"map"] isKindOfClass:[NSDictionary class]]) {
    headers = headers[@"map"];
  }
  
  FetchPlugin *__weak weakSelf = self;
  urlString = [urlString stringByReplacingOccurrencesOfString:@"%20" withString:@" "];
  NSCharacterSet *URLFullCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@"@\"\'+#<>[\\]^`{|} "] invertedSet];
  NSString *encodedString = [urlString stringByAddingPercentEncodingWithAllowedCharacters:URLFullCharacterSet];
  NSURLSessionDataTask *dataTask = [[BaseClient sharedClient] dataTaskWithHTTPMethod:method URLString:encodedString parameters:body headers:headers success:^(NSURLSessionDataTask *task, id responseObject) {

    NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:[NSNumber numberWithInteger:response.statusCode] forKey:@"status"];
    
    if ([response respondsToSelector:@selector(allHeaderFields)]) {
        [result setObject:[self parseHeaderFields:response] forKey:@"headers"];
    }
    
    if (response.URL != nil && response.URL.absoluteString != nil) {
      [result setObject:response.URL.absoluteString forKey:@"url"];
    }
    
    if (responseObject !=nil && [responseObject isKindOfClass:[NSData class]]) {
        
        responseObject = [self cleanUTF8:responseObject];
        
      NSMutableString *resultString = [[NSMutableString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
          
        if (resultString == nil) {
            resultString = [[NSMutableString alloc] initWithData:responseObject encoding:NSNEXTSTEPStringEncoding];
        }
        
      [result setObject:resultString forKey:@"statusText"];
    }
    
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
    [pluginResult setKeepCallbackAsBool:YES];
    [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
  } failure:^(NSURLSessionTask *task, NSError *error, id responseObject) {
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:[NSNumber numberWithInteger:response.statusCode] forKey:@"status"];
    
    if (response.URL != nil && response.URL.absoluteString != nil) {
      [result setObject:response.URL.absoluteString forKey:@"url"];
    } 
    
    if ([response respondsToSelector:@selector(allHeaderFields)]) {
        [result setObject:[self parseHeaderFields:response] forKey:@"headers"];
    }
    
    [result setObject:[error localizedDescription] forKey:@"error"];

    if (error != nil && responseObject == nil) {
      CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:result];
      [pluginResult setKeepCallbackAsBool:YES];
      [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];

    } else {
      if (responseObject !=nil && [responseObject isKindOfClass:[NSData class]]) {
        [result setObject:[[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding] forKey:@"statusText"];
      }
      
      CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:result];
      [pluginResult setKeepCallbackAsBool:YES];
      [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }
    
  }];
  
  [dataTask resume];
}

- (NSDictionary *)parseHeaderFields: (NSHTTPURLResponse *) response {
    
        NSMutableDictionary *newAllHeaders = [[response allHeaderFields] mutableCopy];
        NSArray *cookies = [NSHTTPCookie
                            cookiesWithResponseHeaderFields:newAllHeaders
                            forURL:response.URL]; // send to URL, return NSArray
        
        NSMutableArray *cookieArray = [NSMutableArray new];
        
        
        for (NSHTTPCookie *cookie in cookies) {
            NSString *dateString = [self reformatDateFromString:[[cookie valueForKey:@"expiresDate"] description]];
            
            [cookieArray addObject:[NSString stringWithFormat: @"%@=%@; Domain=%@; Path=%@; Expires=%@", [cookie valueForKey:@"name"], [cookie valueForKey:@"value"], [cookie valueForKey:@"domain"], [cookie valueForKey:@"path"], dateString]];
        }
        
        if ([cookieArray count] > 0) {
            [newAllHeaders setValue:cookieArray forKey:@"Set-Cookie"];
        }
    
    return newAllHeaders;
}

- (NSString *)reformatDateFromString: (NSString *)dateString {
    // 2016-11-30 20:41:30 +0000    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    // this is imporant - we set our input date format to match our input string
    // if format doesn't match you'll get nil from your string, so be careful
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss Z"];

    NSDate *dateFromString = [dateFormatter dateFromString:dateString];
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"EEE, dd'-'MMM'-'yyyy HH':'mm':'ss Z"];
    
    return [formatter stringFromDate:dateFromString];

}

@end
