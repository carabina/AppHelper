//
//  CoreDataUtils.swift
//  AppHelper
//
//  Created by Evan Xie on 23/01/2018.
//  Copyright © 2018 Sky Bluestar. All rights reserved.
//

import CoreData

public final class CoreDataUtils {
    
    public typealias ContextSaveResultHandler = (_ saveResult: ContextSaveResult) -> Void
    
    public enum ContextSaveResult {
        case success
        case failure(NSError)
    }
    
    public static func save(context: NSManagedObjectContext, isAsync: Bool = false, saveResultHandler: ContextSaveResultHandler? = nil) {
        
        let saveBlock = {
            do {
                try context.save()
                saveResultHandler?(.success)
            } catch {
                saveResultHandler?(.failure(error as NSError))
            }
        }
        
        if context.hasChanges {
            if isAsync {
                context.perform {
                    saveBlock()
                }
            } else {
                context.performAndWait {
                    saveBlock()
                }
            }
        }
    }
    
    public static func reset(context: NSManagedObjectContext, isAsync: Bool = false) {
        let resetBlock = {
            context.reset()
        }
        if isAsync {
            context.perform {
                resetBlock()
            }
        } else {
            context.performAndWait {
                resetBlock()
            }
        }
    }
}
