//
//  CoreDatabase.swift
//  AppHelper
//
//  Created by Evan Xie on 23/01/2018.
//  Copyright © 2018 Sky Bluestar. All rights reserved.
//

import CoreData

public final class CoreDatabase {
    
    public typealias TransactionBlock = () throws -> Void
    public typealias TransactionResultHandler = (_ result: TransactionResult) -> Void
    
    public enum TransactionResult {
        case success
        case failure(NSError)
    }
    
    // MARK: - Public Properties
    
    public var storage: CoreDataTypes.Storage {
        checkDatabaseValidity()
        return _storage
    }
    
    public var schemeModel: CoreDataTypes.SchemeModel {
        checkDatabaseValidity()
        return _schemeModel
    }
    
    public var mainContext: NSManagedObjectContext {
        checkDatabaseValidity()
        return _mainContext
    }
    
    public var backgroundContext: NSManagedObjectContext {
        checkDatabaseValidity()
        return _backgroundContext
    }
    
    public var storeCoordinator: NSPersistentStoreCoordinator {
        checkDatabaseValidity()
        return _storeCoordinator
    }
    
    internal var isDestroyed = false {
        didSet {
            if isDestroyed {
                removeContextDidSaveObserver()
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let _storage: CoreDataTypes.Storage
    private let _schemeModel: CoreDataTypes.SchemeModel
    private let _mainContext: NSManagedObjectContext
    private let _backgroundContext: NSManagedObjectContext
    private let _storeCoordinator: NSPersistentStoreCoordinator
    
    public init(
        storage: CoreDataTypes.Storage,
        schemeModel: CoreDataTypes.SchemeModel,
        mainContext: NSManagedObjectContext,
        backgroundContext: NSManagedObjectContext,
        storeCoordinator: NSPersistentStoreCoordinator) {
        
        _storage = storage
        _schemeModel = schemeModel
        _mainContext = mainContext
        _backgroundContext = backgroundContext
        _storeCoordinator = storeCoordinator
        
        addContextDidSaveObserver()
    }
    
    deinit { removeContextDidSaveObserver() }
    
    // MARK: - Public Functions
    
    public func fetchedResultsController<T>(
        request: NSFetchRequest<T>,
        sectionNameKeyPath: String? = nil,
        cacheName: String? = nil
        ) -> NSFetchedResultsController<T>
    {
        let frc = NSFetchedResultsController<T>(
            fetchRequest: request,
            managedObjectContext: _mainContext,
            sectionNameKeyPath: sectionNameKeyPath,
            cacheName: cacheName)
        return frc
    }
    
    /**
     Execute core data transaction on the giving `NSManagedObjectContext` asynchronously.
     */
    public func perform(
        onContext context: NSManagedObjectContext,
        transaction: @escaping TransactionBlock,
        resultHandler: @escaping TransactionResultHandler
        )
    {
        perform(onContext: context, transaction: transaction, shouldWait: false, resultHandler: resultHandler)
    }
    
    /**
     Execute core data transaction on the giving `NSManagedObjectContext` synchronously.
     */
    public func performAndWait(
        onContext context: NSManagedObjectContext,
        transaction: @escaping TransactionBlock
        ) -> TransactionResult
    {
        var transactionResult: TransactionResult!
        perform(onContext: context, transaction: transaction, shouldWait: true) { (result) in
            transactionResult = result
        }
        return transactionResult
    }
    
    public func getContext(type: CoreDataTypes.ContextType) -> NSManagedObjectContext {
        checkDatabaseValidity()
        switch type {
        case .main:
            return _mainContext
        case .background:
            return _backgroundContext
        }
    }
    
    public func makeChildContext(
        type: CoreDataTypes.ContextType = .background,
        mergePolicyType: NSMergePolicyType = .mergeByPropertyObjectTrumpMergePolicyType
        ) -> NSManagedObjectContext {
        
        checkDatabaseValidity()
        
        let childContext = NSManagedObjectContext(concurrencyType: type.rawValue)
        childContext.mergePolicy = NSMergePolicy(merge: mergePolicyType)
        
        switch type {
        case .main:
            childContext.parent = _mainContext
        case .background:
            childContext.parent = _backgroundContext
        }
        
        if let name = childContext.parent?.name {
            childContext.name = name + ".child"
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleChildContextDidSave),
            name: .NSManagedObjectContextDidSave,
            object: childContext
        )
        return childContext
    }
    
    /**
     Rebuild database will delete the database file, all your data will be lost.
     */
    public func rebuild(resultHandler: @escaping CoreDataTypes.CreateDatabaseResultHandler) {
        
        checkDatabaseValidity()
        
        // Remove context did save observer first, when rebuild finishes, add observer again
        removeContextDidSaveObserver()
        
        CoreDatabaseFactory.workingQueue.async { [unowned self] in
            
            defer {
                // Rebuild finishes, add context did save observer again
                self.addContextDidSaveObserver()
            }
            
            guard let store = self.storeCoordinator.persistentStores.first else {
                CoreDataUtils.reset(context: self.mainContext, isAsync: false)
                CoreDataUtils.reset(context: self.backgroundContext, isAsync: false)
                DispatchQueue.main.async { resultHandler(.success(self)) }
                return
            }
            
            do {
                let options = store.options
                try self.storeCoordinator.remove(store)
                try CoreDatabaseFactory.removePersistentStoreDiskFiles(storage: self.storage)
                try self.storeCoordinator.addPersistentStore(
                    ofType: self.storage.rawValue,
                    configurationName: nil,
                    at: self.storage.url,
                    options: options
                )
                
                DispatchQueue.main.async { resultHandler(.success(self)) }
            } catch {
                DispatchQueue.main.async { resultHandler(.failure(error as NSError)) }
            }
        }
    }
}

// MARK: - Private Functions

fileprivate extension CoreDatabase {
    
    /**
     A common function for commiting transaction to `NSManagedObjectContext` in database.
     
     @param resultHandler
     Invoked on the main thread
     */
    func perform(
        onContext context: NSManagedObjectContext,
        transaction: @escaping TransactionBlock,
        shouldWait: Bool,
        resultHandler: @escaping TransactionResultHandler)
    {
        let task = {
            do {
                try transaction()
                if context.hasChanges {
                    try context.save()
                }
                
                if shouldWait {
                    resultHandler(.success)
                } else {
                    DispatchQueue.main.async { resultHandler(.success) }
                }
            } catch {
                if shouldWait {
                    resultHandler(.failure(error as NSError))
                } else {
                    DispatchQueue.main.async { resultHandler(.failure(error as NSError)) }
                }
            }
        }
        
        switch context.concurrencyType {
        case .mainQueueConcurrencyType:
            
            if shouldWait {
                if Thread.isMainThread {
                    task()
                } else {
                    context.performAndWait { task() }
                }
            } else {
                context.perform { task() }
            }
            
        case .privateQueueConcurrencyType:
            
            if shouldWait {
                context.performAndWait { task() }
            } else {
                context.perform { task() }
            }
            
        default:
            fatalError("Don't support NSMangedObjectContext concurrency type: \(context.concurrencyType)")
        }
    }
    
    func checkDatabaseValidity() {
        guard !isDestroyed else {
            fatalError("CoreDatabase has already destroyed, please create CoreDatabase first.")
        }
    }
    
    func addContextDidSaveObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMainContextDidSave),
            name: .NSManagedObjectContextDidSave,
            object: _mainContext
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBackgroundContextDidSave),
            name: .NSManagedObjectContextDidSave,
            object: _backgroundContext
        )
    }
    
    func removeContextDidSaveObserver() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func handleMainContextDidSave(_ notification: Notification) {
        _backgroundContext.perform { [weak self] in
            self?.backgroundContext.mergeChanges(fromContextDidSave: notification)
        }
    }
    
    @objc func handleBackgroundContextDidSave(_ notification: Notification) {
        _mainContext.perform { [weak self] in
            self?.mainContext.mergeChanges(fromContextDidSave: notification)
        }
    }
    
    @objc func handleChildContextDidSave(_ notification: Notification) {
        if let context = notification.object as? NSManagedObjectContext {
            if let parentContext = context.parent {
                CoreDataUtils.save(context: parentContext, isAsync: true)
            }
        }
    }
}
