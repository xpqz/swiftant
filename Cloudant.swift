//
//  Cloudant.swift
//  SwiftAnt
//
//  Swift-wrapper for Cloudant's CDTDatastore. See https://github.com/cloudant/CDTDatastore
//
//  Xcode6 (GM)
//
//  Created by Stefan Kruger on 19/08/2014.
//  Copyright (c) 2014 Stefan Kruger. All rights reserved.
//

import Foundation

typealias handlerBlock = () -> Void

/// Required glue code to make NSFastEnumeration types work in Swift

extension CDTQueryResult: SequenceType {
    public func generate() -> NSFastGenerator {
        return NSFastGenerator(self)
    }
}

/// Swift-wrapper for Cloudant's CDTDatastore. See https://github.com/cloudant/CDTDatastore

class Cloudant: NSObject, CDTReplicatorDelegate {
    
    /**
        Abstraction for a Cloudant connection dealing with bi-directional replication and indexing.
    */
    
    var username:String
    var apiPassword:String
    var apiKey:String
    var database:String
    
    var manager:CDTDatastoreManager
    var datastore:CDTDatastore
    var replicatorFactory:CDTReplicatorFactory?
    var replicator:CDTReplicator?
    var replHandler: handlerBlock?
    var indexManager:CDTIndexManager?
    
    var urlBase:String {
        return "https://\(apiKey):\(apiPassword)@\(username).cloudant.com/\(database)"
    }
    
    /**
    
        Create a Cloudant instance talking to a specified database.
    
        :param: database The name of the Cloudant database
        :param: username Account owner
        :param: key API key
        :param: password API password
    
    */
    
    init(database:String, username:String, key:String, password:String) {
        self.database    = database
        self.username    = username
        self.apiKey      = key
        self.apiPassword = password
        
        // Set up the local data store
        var error: NSError?

        let fileManager  = NSFileManager.defaultManager()
        let documentsDir = fileManager.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)[0] as NSURL
        let storeURL     = documentsDir.URLByAppendingPathComponent("cloudant-sync-datastore")
        let path         = storeURL.path
        
        manager = CDTDatastoreManager(directory: path, error: &error)
        if let err = error {
            println("Error creating datastore manager: \(err.localizedDescription)")
        }
        
        datastore = manager.datastoreNamed(database, error: &error)
        if let err = error {
            println("Error creating datastore: \(err.localizedDescription)")
        }
        
        indexManager = CDTIndexManager(datastore: datastore, error: &error)
        if let err = error {
            println("Error creating index manager: \(err.localizedDescription)")
        }
        
        // Create and start the replicator factory
        replicatorFactory = CDTReplicatorFactory(datastoreManager: manager)
        replicatorFactory!.start()

        super.init()
    }
    
    /**
    
        Start a pull replication - Cloudant -> local database
        
        :param: completionHandler Closure to run on completion: () -> Void
    
    */
    
    func startPullReplicationWithHandler(completionHandler: handlerBlock) {
        var error: NSError?

        // Make a pull replicator, with ourself as the delegate?
        let replication = CDTPullReplication(source: NSURL(string: urlBase), target: datastore)
        replicator = replicatorFactory!.oneWay(replication, error: &error)
        if let err = error {
            println("Error creating replicator: \(err.localizedDescription)")
            return
        }
        
        replHandler = completionHandler
        
        replicator!.delegate = self
        
        replicator!.start()
    }
    
    /**
    
        Start a push replication - local database-> Cloudant
        
        :param: completionHandler Closure to run on completion: () -> Void
    
    */
    
    func startPushReplicationWithHandler(completionHandler: handlerBlock) {
        var error: NSError?
        
        // Make a pull replicator, with ourself as the delegate?
        let replication = CDTPushReplication(source: datastore, target: NSURL(string: urlBase))
        replicator = replicatorFactory!.oneWay(replication, error: &error)
        if let err = error {
            println("Error creating replicator: \(err.localizedDescription)")
            return
        }
        
        replHandler = completionHandler
        
        replicator!.delegate = self
        
        replicator!.start()
    }

    /**
    
        Bi-directional sync - pull-push. Posts a notification CDTSyncCompleted on successful completion.
    
    */

    func sync() {
        startPullReplicationWithHandler { [ unowned self ] in
            self.startPushReplicationWithHandler {
                NSNotificationCenter.defaultCenter().postNotificationName("CDTSyncCompleted", object: nil)
            }
        }
    }
    
    /**
    
        Create a new document and save it in the local database. Note that it will not be pushed automatically.
        
        :param: body NSDictionary describing the document
        :returns: the new document as a CDTDocumentRevision?
    
    */
    
    func save(body: NSDictionary) -> CDTDocumentRevision? {
        var mrev = CDTMutableDocumentRevision()
        mrev.setBody(body)
        var error: NSError?

        let revision = datastore.createDocumentFromRevision(mrev, error: &error)
        if let err = error {
            println("An error occurred saving to the database: \(err.localizedDescription)")
            return nil
        }
        
        updateIndexes()
        
        return revision
    }
    
    /**
    
        Fetch a document on document id.
    
        :param: docid Document id
        :returns: the document as a CDTDocumentRevision?
    
    */
    
    func document(docid: String) -> CDTDocumentRevision? {
        var error: NSError?
        let retrieved = datastore.getDocumentWithId(docid, error: &error)
        if let err = error {
            println("Error fetching document '\(docid)': \(err.localizedDescription)")
            return nil
        }
        
        return retrieved
    }
    
    // MARK: - Indexing & querying
    
    func ensureIndexedWithName(indices: [String: String]) {
        if let im = indexManager {
            var error: NSError?
            for (indexName, fieldName) in indices {
                im.ensureIndexedWithIndexName(indexName, fieldName: fieldName, error: &error)
                if let err = error {
                    println("Indexing error for (\(indexName): \(fieldName)): \(err.localizedDescription)")
                }
            }
        }
    }
    
    func updateIndexes() {
        var error: NSError?
        self.indexManager?.updateAllIndexes(&error)
        
        if let err = error {
            println("Error updating indexes: \(err.localizedDescription)")
        }
    }
    
    func query(parameters: [String: String]) -> CDTQueryResult? {
        if let im = indexManager {
            var error: NSError?
            let result = im.queryWithDictionary(parameters, error: &error)
            
            if let err = error {
                println("Error querying index: \(err.localizedDescription)")
                return nil
            }
            
            return result
        }
        
        return nil
    }
    
    // MARK: - CDTReplicatorDelegate
    
    func replicatorDidComplete(replicator: CDTReplicator!) {
        if let handler = replHandler {
            handler()
            NSNotificationCenter.defaultCenter().postNotificationName("CDTReplicationCompleted", object: nil)
        }
    }
    
    func replicatorDidChangeProgress(replicator: CDTReplicator!) {

    }
    
    func replicatorDidChangeState(replicator: CDTReplicator!) {

    }
    
    func replicatorDidError(replicator: CDTReplicator!, info: NSError!) {
        let state = CDTReplicator.stringForReplicatorState(replicator!.state)
        println("\(state): \(info.localizedDescription)")
    }
}


