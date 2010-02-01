
//  SwizzleKit
//  Created by Scott Morrison on 12/01/09.
//  ------------------------------------------------------------------------
//  Copyright (c) 2009, Scott Morrison .
//  Some licensing details are going to be here at some point in the future
//
//  ------------------------------------------------------------------------


// Underimplemented!!!! 
//
// This is a work in progress.   somethings probaby won't work. 
// have fun!


#import <Cocoa/Cocoa.h>
#import <objc/objc-class.h>
#include <execinfo.h>
#include <stdio.h>


#define BUNDLE_IDENTIFIER @"com.yourBundle.identifier"


//  Unique Prefixes
//
// if you are using SwizzleKit for use in plugins into host applications, there is the possibility of multiple plugins using swizzlekit, leading to naming collisions.   Defining a unique prefix should prevent this (unless, ofcourse, you use a prefix already in use.
// usage:
//
//	perfom a find and replace of UNIQUE_PREFIX with the unique prefix for your bundle \




// working with private classes necessitates performing lookups of hidden classes at runtime in order to properly extend classes and swizzle methods etc.
// define a convenience macro to perform this frequently used call.

#define CLS(className) NSClassFromString([NSString stringWithFormat:@"%s",#className])

// if you dynamicly subclass a hidden class at runtime, using another (NSObject) class as a template, there is a problem using [super method] message sending as the super keyword will
// refer to the compiled superclass, not the target superclass.  the SUPER(...) macro will look up the target superclass at runtime and send the message to this class.
// NOTE  this will return a NSObject * result.  If you need to have a struct result, you will need to use objc_msgSendSuper_stret function.  Do your research.

#define SUPER(...)  objc_msgSendSuper(&(struct objc_super){self, class_getSuperclass([self class])},_cmd, ##__VA_ARGS__)


//respondsDirectlyToSelector method returns YES if this object implements the selector directly.  
// 									Returns NO if any superclass implements the selector or no superclass implemention.

@interface NSObject (UNIQUE_PREFIXswizzleKit) 
	-(BOOL)UNIQUE_PREFIXrespondsDirectlyToSelector:(SEL)aSelector;
@end


// describeClass is a quick and dirty function to be called in gdb to get the details of a class (ivars, methods, super methods etc)

void UNIQUE_PREFIXdescribeClass(const char * clsName);


// BACKTRACE MACRO
// This is used in debugging and code analysis
//  adding BACKTRACE(NO|YES) to a swizzled method will log out the backtrace to console and continue (or break)
#define BACKTRACE(shouldBreak) \
	NSLog(@"----------- DEBUG ----------\nSelf: %@\n Thread: %@\nThreadDictionary: %@\nBackTrace %@",self, [NSThread currentThread],[[NSThread currentThread] threadDictionary],[NSThread abbreviatedCallStackSymbols]); \
	if (shouldBreak){ \
		Debugger(); \
	} \


// the following macro will implement a maptable for a class for the maintenace of extra 'ivars' for an object.
// in doing so it will swizzle the dealloc method for PREFIX_MapTable_dealloc
// the PREFIX_MapTable_dealloc will call PREFIX_dealloc if it exists so that any other clean up can be done bereo the mapTable variabls are released.
// It will also create a class Method +mapTable that will create the maptable on the first call (access though the accessors function above.

// The mapTableVariables should be accessed ONLY through the use of the functions declared above
// 
	
#define IMPLEMENT_MAPTABLE_VARIABLES_USING_PREFIX(prefix) \
	static NSMapTable	*_mappedViewerIVars = NULL; \
	static NSLock * _mapTableLock = nil; \
	\
		+(NSMapTable* )mapTable{ \
		if (!_mappedViewerIVars){ \
			_mappedViewerIVars = NSCreateMapTableWithZone(NSNonOwnedPointerMapKeyCallBacks, NSObjectMapValueCallBacks, 3, [self zone]); \
			_mapTableLock= [[NSLock alloc] init]; \
			Method oldDeallocMethod = class_getInstanceMethod(self, @selector(dealloc)); \
			Method newDeallocMethod = class_getInstanceMethod(self, @selector(##prefix_MapTable_dealloc)); \
			__originalDeallocIMP = method_getImplementation(oldDeallocMethod); /* this may be handy to keep around */ \
			NSAssert (oldDeallocMethod && newDeallocMethod ,@"Could not swizzle a dealloc method for MapTable Implementation"); \
			/* try to add a dealloc method to this class -- if successful,then redirect the dealloc method to ##prefix_MapTable_dealloc */   \
			/*  Technique taken from Mike Ash http://mikeash.com/?page=pyblog/friday-qa-2010-01-29-method-replacement-for-fun-and-profit.html*/ \
			if (class_addMethod(self, @selector(dealloc), method_getImplementation(newDeallocMethod), method_getTypeEncoding(newDeallocMethod))){ \
					class_replaceMethod(self,@selector(##prefix_MapTable_dealloc),method_getImplementation(oldDeallocMethod), method_getTypeEncoding(newDeallocMethod)); \
			} \
			else { \
				/* not successful in adding a dealloc  method so just do a straightup swizzle. */ \
				method_exchangeImplementations(oldDeallocMethod, newDeallocMethod); \
			}  \
		} \
		[_mapTableLock lock]; \
		id mapTable = [_mappedViewerIVars retain]; \
		[_mapTableLock unlock]; \
		return [mapTable autorelease]; \
	} \
	 \
	- (void)##prefix_MapTable_dealloc{ \
		if([self respondsDirectlyToSelector:@selector(##prefixdealloc)]) \
			[self ##prefixdealloc]; \
		[_mapTableLock lock]; \
		if(_mappedViewerIVars){ \
			NSMapRemove(_mappedViewerIVars,self);  \
		} \
		[_mapTableLock unlock]; \
		[self ##prefix_MapTable_dealloc]; \
	} \
	\
	- (id) ##prefixvariables{ \
		id anObject = self; \
		static NSMapTable * mapTable = nil; \
		if (!mapTable){ \
			if ([[anObject class] respondsToSelector:@selector(mapTable)]){ \
				mapTable  = [[anObject class] mapTable]; \
			} \
		} \
		id theValue = nil; \
		if (mapTable){ \
			NSMutableDictionary	*aDict = nil; \
			@synchronized(mapTable){ \
				aDict = [NSMapGet(mapTable, anObject) retain]; \
			} \
			return [aDict autorelease]; \
		} \
		return nil; \
		 \
	} \
	- (id) ##prefixvariable:(NSString*) variableName{ \
		id anObject = self; \
		static NSMapTable * mapTable = nil; \
		if (!mapTable){ \
			if ([[anObject class] respondsToSelector:@selector(mapTable)]){ \
				mapTable  = [[anObject class] mapTable]; \
			} \
		} \
		id theValue = nil; \
		if (mapTable){ \
			@synchronized(mapTable){ \
				NSMutableDictionary	*aDict; \
				aDict = NSMapGet(mapTable, anObject); \
				if (nil == aDict){ \
					aDict = [NSMutableDictionary dictionary]; \
					NSMapInsert(mapTable, anObject, aDict); \
				} \
				theValue = [aDict objectForKey:variableName ] ; \
			} \
		} \
		return [[theValue retain] autorelease]; \
	} \
	- (void) set##prefixvariable:( NSString*)variableName toValue:(id) value{ \
		id anObject= self; \
		static NSMapTable * mapTable = nil; \
		if (!mapTable){ \
			if ([[anObject class] respondsToSelector:@selector(mapTable)]){ \
				mapTable  = [[anObject class] mapTable]; \
			} \
		} \
		if (mapTable){ \
			@synchronized(mapTable){ \
				NSMutableDictionary	*aDict; \
				aDict = NSMapGet(mapTable, anObject); \
				if (nil == aDict){ \
					aDict = [NSMutableDictionary dictionary]; \
					NSMapInsert(mapTable, anObject, aDict); \
				} \
				if (value){ \
					[aDict setObject:value forKey:variableName]; \
				} \
				else{ \
					[aDict removeObjectForKey:variableName]; \
				} \
			} \
		} \
		 \
	} \


id UNIQUE_PREFIXobject_getMapTableVariable(id anObject, const char* variableName); 
void UNIQUE_PREFIXobject_setMapTableVariable(id anObject, const char* variableName,id value); 



// declare functions for getting MapTabled variables.
// The functions should be thread safe (using @synchronize)
// note that because of the nature of mapTables, the setter will always retain the value passed in.
//   make copies prior to adding to the function
// for assignment, wrap the value in an NSValue Object.



// The following Macros standardize the creation of getters and setters for ivars
#define IVAR_OBJECT_GETTER(getterName,ivarName) \
	-(id)getterName{ \
		static Ivar ivar =0; \
		if (!ivar) \
			ivar = class_getInstanceVariable([self class], #ivarName); \
		return [[object_getIvar(self, ivar) retain] autorelease]; \
	} \

#define IVAR_OBJECT_SETTER_RETAIN(setterName,ivarName) \
	-(void)setterName:(id)value { \
		static Ivar ivar =0; \
		if (!ivar) \
			ivar = class_getInstanceVariable([self class], #ivarName); \
		id old = object_getIvar(self, ivar);  \
		static NSMutableString* key=0; \
		if (!key) { \
			key=[[NSMutableString alloc] initWithFormat:@"%s",#setterName]; \
			NSString * keyInitial =[key substringWithRange:NSMakeRange(3,1)]; \
			[key replaceCharactersInRange:NSMakeRange(0,4) withString:keyInitial]; \
		}\
		[self willChangeValueForKey: key]; \
		object_setIvar(self,ivar,[value retain]); \
		[self didChangeValueForKey: key]; \
		[old release]; \
	} \

#define IVAR_OBJECT_SETTER_COPY(setterName,ivarName) \
	-(void)setterName:(id)value { \
		static Ivar ivar =0; \
		if (!ivar) \
			ivar = class_getInstanceVariable([self class], #ivarName); \
		id old = object_getIvar(self, ivar); \
		static NSMutableString* key =0; \
		if (!key) { \
			key=[[NSMutableString alloc] initWithFormat:@"%s",#setterName]; \
			NSString * keyInitial =[key substringWithRange:NSMakeRange(3,1)]; \
			[key replaceCharactersInRange:NSMakeRange(0,4) withString:keyInitial]; \
		}\
		[self willChangeValueForKey: key]; \
		object_setIvar(self,ivar,[value copy]); \
		[self didChangeValueForKey: key]; \
		[old release]; \
	} \

#define IVAR_OBJECT_SETTER_ASSIGN(setterName,ivarName) \
	-(void)setterName:(id)value { \
		static Ivar ivar =0; \
		if (!ivar) \
			ivar = class_getInstanceVariable([self class], #ivarName); \
		static NSMutableString* key =0; \
		if (!key) { \
			key=[[NSMutableString alloc] initWithFormat:@"%s",#setterName]; \
			NSString * keyInitial =[key substringWithRange:NSMakeRange(3,1)]; \
			[key replaceCharactersInRange:NSMakeRange(0,4) withString:keyInitial]; \
		}\
		[self willChangeValueForKey: key]; \
		object_setIvar(self,ivar,value); \
		[self didChangeValueForKey: key]; \
	} \

#define IVAR_OBJECT_ACCCESSORS_RETAIN(getterName,setterName,ivarName) \
	IVAR_OBJECT_GETTER(getterName,ivarName) \
	IVAR_OBJECT_SETTER_RETAIN(setterName,ivarName)

#define IVAR_OBJECT_ACCCESSORS_COPY(getterName,setterName,ivarName) \
	IVAR_OBJECT_GETTER(getterName,ivarName) \
	IVAR_OBJECT_SETTER_COPY(setterName,ivarName)

#define IVAR_OBJECT_ACCCESSORS_ASSIGN(getterName,setterName,ivarName) \
	IVAR_OBJECT_GETTER(getterName,ivarName) \
	IVAR_OBJECT_SETTER_ASSIGN(setterName,ivarName)


#define IVAR_TYPE_GETTER(getterName,ivarName,type) \
	-(type)getterName{ \
		static Ivar ivar =0; \
		if (!ivar) \
			ivar = class_getInstanceVariable([self class], #ivarName); \
		NSInteger offset = ivar_getOffset(ivar); \
		type result =*(type*) ((NSInteger)self + offset); \
		return result; \
	}

#define IVAR_TYPE_SETTER(setterName,ivarName,type) \
	-(void)setterName:(type)value{ \
		static Ivar ivar =0; \
		if (!ivar) \
			ivar = class_getInstanceVariable([self class], #ivarName); \
		static NSMutableString* key=0; \
		if (!key) { \
			key=[[NSMutableString alloc] initWithFormat:@"%s",#setterName]; \
			NSString * keyInitial =[key substringWithRange:NSMakeRange(3,1)]; \
			[key replaceCharactersInRange:NSMakeRange(0,4) withString:keyInitial]; \
		}\
		NSInteger offset = ivar_getOffset(ivar); \
		[self willChangeValueForKey: key]; \
		*(type*)((NSInteger)self + offset)=value; \
		[self didChangeValueForKey: key]; \
	}



@interface UNIQUE_PREFIXSwizzler : NSObject{
}
+(void)setPrefix:(NSString*)prefix;
+(void)setProviderSuffix:(NSString*)suffix;
+(Class)subclass:(Class)baseClass usingClassName:(NSString*)subclassName providerClass:(Class)providerClass;
+(void)extendClass:(Class) targetClass withMethodsFromClass:(Class)providerClass;
+(BOOL)addClassMethodName:(NSString *)methodName fromProviderClass:(Class)providerClass toClass:(Class)targetClass;
+(BOOL)addInstanceMethodName:(NSString *)methodName fromProviderClass:(Class)providerClass toClass:(Class)targetClass;
+(IMP)swizzleClassMethod:(NSString*)methodName forClass:(Class)targetClass;
+(IMP)swizzleInstanceMethod:(NSString*)methodName forClass:(Class)targetClass;


@end


@end


@interface NSThread (SwizzleKit)
+(NSArray*)abbreviatedCallStackSymbols;
@end


