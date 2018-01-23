//
//  CoreDatabaseFactory.swift
//  AppHelper
//
//  Created by Evan Xie on 23/01/2018.
//  Copyright © 2018 Sky Bluestar. All rights reserved.
//

import CoreData

public struct CoreDatabaseFactory {
    
    // MARK: - Default Values
    
    public static let defaultStorageDirectoryPath: NSString = {
        return NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0] as NSString
    }()
    
    public static let defaultStorage: CoreDataTypes.Storage = {
        let storageName = "\(defaultSchemeModel.name).\(CoreDataTypes.ModelFileExtension.sqlite.rawValue)"
        let storagePath = defaultStorageDirectoryPath.appendingPathComponent(storageName)
        return CoreDataTypes.Storage.sqlite(URL(fileURLWithPath: storagePath))
    }()
    
    public static let defaultStoreOptions: CoreDataTypes.PersistentStoreOptions = [
        NSMigratePersistentStoresAutomaticallyOption: true,
        NSInferMappingModelAutomaticallyOption: true
    ]
    
    public static let defaultSchemeModel: CoreDataTypes.SchemeModel = {
        return CoreDataTypes.SchemeModel(name: Bundle.main.infoDictionary!["CFBundleName"] as! String)
    }()
    
    internal static let workingQueue: DispatchQueue = {
        return DispatchQueue(label: "CoreDatabase.workingQueue")
    }()
    
    // MARK: - Public Functions
    
    public static func storageURL(shcemeModelName: String, storageDirectory: NSString = defaultStorageDirectoryPath) -> URL {
        let storageName = "\(shcemeModelName).\(CoreDataTypes.ModelFileExtension.sqlite.rawValue)"
        let storagePath = storageDirectory.appendingPathComponent(storageName)
        return URL(fileURLWithPath: storagePath)
    }
    
    public static func createCoreDatabase(
        schemeModel: CoreDataTypes.SchemeModel = defaultSchemeModel,
        storage: CoreDataTypes.Storage = defaultStorage,
        options: CoreDataTypes.PersistentStoreOptions = defaultStoreOptions,
        resultHandler: @escaping CoreDataTypes.CreateDatabaseResultHandler){
        
        workingQueue.async {
            do {
                let coordinator = try createStoreCoordinator(objectModel: schemeModel.objectModel, storage: storage, options: options)
                let mainContext = createContext(type: .main, storeCoordinator: coordinator)
                let backgroundContext = createContext(type: .background, storeCoordinator: coordinator)
                let database = CoreDatabase(
                    storage: storage,
                    schemeModel: schemeModel,
                    mainContext: mainContext,
                    backgroundContext: backgroundContext,
                    storeCoordinator: coordinator
                )
                DispatchQueue.main.async { resultHandler(.success(database)) }
            } catch {
                DispatchQueue.main.async { resultHandler(.failure(error as NSError)) }
            }
        }
    }
    
    /**
     After destorying database, the related `CoreDatabase` instance is invalid, and you can not
     access `mainContext`, `backgroundContext` any more, or you'll encounter a crash.
     
     If you want to access database again, please create `CoreDatabase` first.
     */
    public static func destoryCoreDatabase(database: CoreDatabase, resultHandler: @escaping CoreDataTypes.DestroyDatabaseResultHandler) {
        workingQueue.async {
            
            guard !database.isDestroyed else {
                DispatchQueue.main.async { resultHandler(.success) }
                return
            }
            
            CoreDataUtils.reset(context: database.mainContext, isAsync: false)
            CoreDataUtils.reset(context: database.backgroundContext, isAsync: false)
            
            let coordinator = database.storeCoordinator
            guard let store = coordinator.persistentStores.first else {
                database.isDestroyed = true
                DispatchQueue.main.async { resultHandler(.success) }
                return
            }
            
            do {
                try coordinator.remove(store)
                try removePersistentStoreDiskFiles(storage: database.storage)
                database.isDestroyed = true
                DispatchQueue.main.async { resultHandler(.success) }
            } catch {
                DispatchQueue.main.async { resultHandler(.failure(error as NSError)) }
            }
        }
    }
    
    // MARK: - Internal Functions
    
    internal static func createPersistentStoreParentDirectory(storage: CoreDataTypes.Storage) {
        if let storeParentDirectoryURL = storage.url?.deletingLastPathComponent() {
            try? FileManager.default.createDirectory(
                at: storeParentDirectoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
    
    internal static func removePersistentStoreDiskFiles(storage: CoreDataTypes.Storage) throws {
        
        guard let storePath = storage.url?.path else { return }
        
        let walPath = storePath + "-wal" // Write Ahead Log
        let shmPath = storePath + "-shm" // Shared Memory
        
        if FileManager.default.fileExists(atPath: storePath) {
            try FileManager.default.removeItem(atPath: storePath)
        }
        
        if FileManager.default.fileExists(atPath: walPath) {
            try FileManager.default.removeItem(atPath: walPath)
        }
        
        if FileManager.default.fileExists(atPath: shmPath) {
            try FileManager.default.removeItem(atPath: shmPath)
        }
    }
}

// MARK: - Private Functions

fileprivate extension CoreDatabaseFactory {
    
    static func createStoreCoordinator(
        objectModel: NSManagedObjectModel,
        storage: CoreDataTypes.Storage,
        options: CoreDataTypes.PersistentStoreOptions) throws -> NSPersistentStoreCoordinator  {
        
        createPersistentStoreParentDirectory(storage: storage)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: objectModel)
        try coordinator.addPersistentStore(
            ofType: storage.rawValue,
            configurationName: nil,
            at: storage.url,
            options: options
        )
        return coordinator
    }
    
    static func createContext(type: CoreDataTypes.ContextType, storeCoordinator: NSPersistentStoreCoordinator) -> NSManagedObjectContext {
        let context = NSManagedObjectContext(concurrencyType: type.rawValue)
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyStoreTrumpMergePolicyType)
        context.name = "CoreDatabase.Context.\(type.name)"
        context.persistentStoreCoordinator = storeCoordinator
        return context
    }
}
