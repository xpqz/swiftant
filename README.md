swiftant
========

Swift wrapper for Cloudant's CDTDatastore

To use, install the Cloudant libs from https://github.com/cloudant/CDTDatastore and put 

```objc
#import <CloudantSync.h>
```

in your bridging header. Then you can do something like this:

```swift
var cloudant = Cloudant(database: "dabname", username: "ca-user", key: "api-key", password: "api-secret")

cloudant.startPullReplicationWithHandler {
	println("Replication complete")
}

// Pull out a known document
if let doc = cloudant.document("7a36cbc16e43e362e1ae68861aa0168f") {
	println(doc.body())
}

// Create and save a new document
if let docRev = cloudant.save(dictionary) {
	println("Document saved as \(docRev.docId)")
}

// Bi-directional sync. Will post a "CDTSyncCompleted" notification when done.
cloudant.sync()

// Create an index
cloudant.ensureIndexedWithName(["schema": "schema"])

// Query index, and update a table view - 'datasource' instance var holding the data. 'Item' some model class.
func reload() {
    if let result = cloudant.query(["schema": "item"]) {
        datasource = [Item]()
        for revision in result {
			let rev = revision as CDTDocumentRevision
			let item = Item(rev.td_rev.properties)
			datasource.append(item)
        }
    }
    tableView.reloadData()
}

```