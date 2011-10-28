
//  SwizzleKit
//  Created by Scott Morrison on 12/01/09.
//  ------------------------------------------------------------------------
//  Copyright (c) 2009, Scott Morrison All rights reserved.
//
//
//  ------------------------------------------------------------------------

#import "SwizzleKit.m"
#define SWIZZLE_PREFIX @"UNIQUE_PREFIX"
#define PROVIDER_SUFFIX @"UNIQUE_PREFIX"

@implementation NSObject (UNIQUE_PREFIXSwizzleKit)

-(BOOL)UNIQUE_PREFIXrespondsDirectlyToSelector:(SEL)aSelector{
	BOOL responds = NO;
	unsigned int methodCount = 0;
	Method * methods = nil;

	// extend instance Methods
	methods = class_copyMethodList([self class], &methodCount);
	int ci= methodCount;
	while (methods && ci--){
		if (method_getName(methods[ci]) == aSelector){
			responds = YES;
			break;
		}
	}
	free(methods);
	return responds;
}

@end


id UNIQUE_PREFIXobject_getMapTableVariable(id anObject, const char* variableName){
	static NSMapTable * mapTable = nil;
	if (!mapTable){
		if ([[anObject class] respondsToSelector:@selector(mapTable)]){
			mapTable  = [[anObject class] mapTable];
		}
	}
	id theValue = nil;
	if (mapTable){
		@synchronized(mapTable){
			NSMutableDictionary	*aDict;
			aDict = NSMapGet(mapTable, anObject);
			if (nil == aDict){
				aDict = [NSMutableDictionary dictionary];
				NSMapInsert(mapTable, anObject, aDict);
			}
			theValue = [aDict objectForKey:[NSString stringWithFormat:@"%s",variableName] ] ;
		}
	}
	return theValue;
}

void UNIQUE_PREFIXobject_setMapTableVariable(id anObject, const char* variableName,id value){
	static NSMapTable * mapTable = nil;
	if (!mapTable){
		if ([[anObject class] respondsToSelector:@selector(mapTable)]){
			mapTable  = [[anObject class] mapTable];
		}
	}
	if (mapTable){
		@synchronized(mapTable){
			NSMutableDictionary	*aDict;
			aDict = NSMapGet(mapTable, anObject);
			if (nil == aDict){
				aDict = [NSMutableDictionary dictionary];
				NSMapInsert(mapTable, anObject, aDict);
			}
			if (value){
				[aDict setObject:value forKey:[NSString stringWithFormat:@"%s",variableName]];
			}
			else{
				[aDict removeObjectForKey:[NSString stringWithFormat:@"%s",variableName]];
			}
		}
	}

}

void UNIQUE_PREFIXdescribeClass(const char * clsName){
	Class aClass = objc_getClass(clsName);
	if (aClass){
		NSMutableString * logString = [NSMutableString string];
		Class superClass = class_getSuperclass(aClass);
		const char * superClassName = class_getName(superClass);
		[logString appendFormat:@"@interface %s : %s\n{",clsName,superClassName];
		unsigned int ivarCount = 0;
		NSUInteger ci =0;
		Ivar * ivars = class_copyIvarList(aClass, &ivarCount);
		for (ci=0;ci<ivarCount;ci++){
			[logString appendFormat:@"    %s %s; //%ld\n",ivar_getTypeEncoding(ivars[ci]), ivar_getName(ivars[ci]), ivar_getOffset(ivars[ci])];

		}
		[logString appendString:@"}\n"];
		free(ivars);

		unsigned int classMethodCount =0;
		Method *classMethods = class_copyMethodList(object_getClass(aClass), &classMethodCount);
		for(ci=0;ci<classMethodCount;ci++){
			[logString appendFormat:@"+[%s %@]\n",class_getName(aClass),NSStringFromSelector(method_getName(classMethods[ci]))];
		}
		free(classMethods);

		unsigned int instanceMethodCount =0;
		Method *instanceMethods = class_copyMethodList(aClass, &instanceMethodCount);
		for(ci=0;ci<instanceMethodCount;ci++){
			[logString appendFormat:@"-[%s %@]\n",class_getName(aClass),NSStringFromSelector(method_getName(instanceMethods[ci]))];
		}



		NSLog(@"%@",logString);
	}
}

@implementation UNIQUE_PREFIXSwizzler
+(Class)subclass:(Class)baseClass usingClassName:(NSString*)subclassName providerClass:(Class)providerClass{
	Class subclass = objc_allocateClassPair(baseClass, [subclassName UTF8String], 0);
	if (!subclass) return nil;

	unsigned int ivarCount =0;
	Ivar * ivars = class_copyIvarList(providerClass, &ivarCount);
	int ci = 0;
	for (ci=0 ;ci < ivarCount; ci++){
		Ivar anIvar = ivars[ci];

		NSUInteger ivarSize = 0;
		NSUInteger ivarAlignment = 0;
		const char * typeEncoding = ivar_getTypeEncoding(anIvar);
		NSGetSizeAndAlignment(typeEncoding, &ivarSize, &ivarAlignment);
		const char * ivarName = ivar_getName(anIvar);
		NSString * ivarStringName = [NSString stringWithUTF8String:ivarName];
		BOOL addIVarResult = class_addIvar(subclass, ivarName, ivarSize, ivarAlignment, typeEncoding  );
		if (!addIVarResult){
			NSLog(@"could not add iVar %s", ivar_getName(anIvar));
			return nil;
		}

	}
	free(ivars);
	objc_registerClassPair(subclass);

	[self extendClass:subclass withMethodsFromClass:providerClass];
	return subclass;
}
+(void)extendClass:(Class) targetClass withMethodsFromClass:(Class)providerClass{
	unsigned int methodCount = 0;
	Method * methods = nil;

	// extend instance Methods
	methods = class_copyMethodList(providerClass, &methodCount);
	int ci= methodCount;
	while (methods && ci--){
		NSString * methodName = NSStringFromSelector(method_getName(methods[ci]));
		[self addInstanceMethodName:methodName fromProviderClass:providerClass toClass:targetClass];
		//NSLog(@"extending -[%s %@]",class_getName(targetClass),methodName);
	}
	free(methods);

	// extend Class Methods
	methods = class_copyMethodList(object_getClass(providerClass), &methodCount);
	ci= methodCount;
	while (methods && ci--){
		NSString * methodName = NSStringFromSelector(method_getName(methods[ci]));
		[self addClassMethodName:methodName fromProviderClass:providerClass toClass:targetClass];
		//NSLog(@"extending +[%s %@]",class_getName(targetClass),methodName);
	}
	free(methods);

	methods  = 0;
}
+(BOOL)addClassMethodName:(NSString *)methodName fromProviderClass:(Class)providerClass toClass:(Class)targetClass{
	Class metaClass = object_getClass(targetClass);// objc_getMetaClass(class_getName(targetClass));
	if (!metaClass) {
		return NO;
	}
	SEL selector = NSSelectorFromString(methodName);
	Method originalMethod = class_getClassMethod(providerClass,selector);

	if (!originalMethod) {
		return NO;
	}

	IMP originalImplementation  = method_getImplementation(originalMethod);
	if (!originalImplementation){
		return NO;
	}

	class_addMethod(metaClass, selector ,originalImplementation, method_getTypeEncoding(originalMethod));

	return YES;
}

+(BOOL)addInstanceMethodName:(NSString *)methodName fromProviderClass:(Class)providerClass toClass:(Class)targetClass{
	if (!targetClass) {
		return NO;
	}
	SEL selector = NSSelectorFromString(methodName);
	Method originalMethod = class_getInstanceMethod(providerClass,selector);

	if (!originalMethod) {
		return NO;
	}

	IMP originalImplementation  = method_getImplementation(originalMethod);
	if (!originalImplementation){
		return NO;
	}

	class_addMethod(targetClass, selector ,originalImplementation, method_getTypeEncoding(originalMethod));

	return YES;
}

+(IMP)swizzleClassMethod:(NSString*)methodName forClass:(Class)targetClass{
	Method oldMethod, newMethod;
	IMP newIMP = nil;
	SEL oldSelector = NSSelectorFromString(methodName);
	NSString * newMethodName = [SWIZZLE_PREFIX stringByAppendingString:methodName];
	SEL newSelector = NSSelectorFromString(newMethodName);

	oldMethod = class_getClassMethod(targetClass, oldSelector);
	if (oldMethod==NULL) {
		NSLog(@"SWIZZLE Error - Can't find existing method for +[%@ %@]",NSStringFromClass(targetClass),NSStringFromSelector(oldSelector));
		//Debugger();
		return NULL;
	}
	newMethod = class_getClassMethod(targetClass, newSelector);
	if (newMethod==NULL) {
		//look for a provider Class
		NSString * providerClassName = [NSStringFromClass(targetClass) stringByAppendingString:PROVIDER_SUFFIX];
		Class providerClass = NSClassFromString(providerClassName);
		if (providerClass){
			[self addClassMethodName: newMethodName fromProviderClass:providerClass toClass:targetClass];
			newMethod = class_getClassMethod(targetClass, newSelector);
			if (newMethod==NULL) {
				NSLog(@"SWIZZLE Error - Can't find existing method for +[%@ %@]",NSStringFromClass(targetClass),NSStringFromSelector(oldSelector));
				return NULL;
			}
		}
		else{
			NSLog(@"SWIZZLE Error - Can't find existing method for +[%@ %@]",NSStringFromClass(targetClass),NSStringFromSelector(oldSelector));
			return NULL;
		}

		//Debugger();
	}
	if (NULL != oldMethod && NULL != newMethod) {
		//newIMP =
		newIMP= method_getImplementation(oldMethod);
		method_exchangeImplementations(oldMethod, newMethod);

		//newIMP = method_setImplementation(oldMethod,method_getImplementation(newMethod));
		//method_setImplementation(newMethod, newIMP);
		return newIMP;
	}

	return NULL;
}
+(IMP)swizzleInstanceMethod:(NSString*)methodName forClass:(Class)targetClass{
	//NSLog (@"Trying to swizzle %@ method: %@",targetClass,methodName);
	Method oldMethod, newMethod;
	IMP oldIMP = nil;
	SEL oldSelector = NSSelectorFromString(methodName);
	NSString * newMethodName = [SWIZZLE_PREFIX stringByAppendingString:methodName];
	SEL newSelector = NSSelectorFromString(newMethodName);

	oldMethod = class_getInstanceMethod(targetClass, oldSelector);
	if (oldMethod==NULL) {
		NSLog(@"SWIZZLE Error - Can't find existing method for -[%@ %@]",NSStringFromClass(targetClass),NSStringFromSelector(oldSelector));
		//Debugger();
		return NULL;
	}
	newMethod = class_getInstanceMethod(targetClass, newSelector);
	if (newMethod==NULL) {
		//look for a provider Class
		NSString * providerClassName = [NSStringFromClass(targetClass) stringByAppendingString:PROVIDER_SUFFIX];
		Class providerClass = NSClassFromString(providerClassName);
		if (providerClass){
			[self addInstanceMethodName: newMethodName fromProviderClass:providerClass toClass:targetClass];
			newMethod = class_getInstanceMethod(targetClass, newSelector);
			if (newMethod==NULL) {
				NSLog(@"SWIZZLE Error - Can't find existing method for -[%@ %@]",NSStringFromClass(targetClass),NSStringFromSelector(oldSelector));
				return NULL;
			}
		}
		else{
			NSLog(@"SWIZZLE Error - Can't find existing method for -[%@ %@]",NSStringFromClass(targetClass),NSStringFromSelector(oldSelector));
			return NULL;
		}

		//Debugger();
	}
	if (NULL != oldMethod && NULL != newMethod) {
		//newIMP = method_exchangeImplementations(, )
		oldIMP = method_setImplementation(oldMethod,method_getImplementation(newMethod));
		method_setImplementation(newMethod, oldIMP);

		return oldIMP;
	}

	return NULL;
}
@end




@implementation NSThread(SwizzleKit)
+(NSArray*)abbreviatedCallStackSymbols{
	// returns the backtrace as a NSArray of NSStrings, simplifying the addresses etc in the process.
	void* callstack[128];
	int i, frames = backtrace(callstack, 128);
	char** strs = backtrace_symbols(callstack, frames);
	NSMutableArray *callStack = [[NSMutableArray alloc] initWithCapacity:frames];

	for (i = 1; i < frames; ++i) {
		NSString * frameString = [[NSString alloc] initWithUTF8String:strs[i]];
		NSScanner * scanner = [NSScanner scannerWithString:frameString];
		NSString * dummy = nil;
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * frameNumber = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&frameNumber];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * module = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&module];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * address = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&address];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * method = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet] intoString:&method];
		[callStack addObject:[NSString stringWithFormat:@"%3-s %18-s %@",[frameNumber UTF8String],[module UTF8String],method]];

	}
	free(strs);

	return [callStack autorelease];
}

+(NSArray *)callStackSymbolsForFrameCount:(NSInteger) frameCount{
	// will return the most recent <frameCount> stackFrames from the backtrace
	void* callstack[128];
	int i, frames = backtrace(callstack, 128);
	char** strs = backtrace_symbols(callstack, frames);
	NSMutableArray *callStack = [[NSMutableArray alloc] initWithCapacity:frames];
	int maxFrame = MIN(frames,frameCount+1);

	for (i = 1; i < maxFrame; ++i) {
		NSString * frameString = [[NSString alloc] initWithUTF8String:strs[i]];
		NSScanner * scanner = [NSScanner scannerWithString:frameString];
		NSString * dummy = nil;
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * frameNumber = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&frameNumber];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * module = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&module];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * address = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&address];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * method = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet] intoString:&method];
		[callStack addObject:[NSString stringWithFormat:@"%3-s %18-s %@",[frameNumber UTF8String],[module UTF8String],method]];

	}
	free(strs);

	return [callStack autorelease];

}
@end

