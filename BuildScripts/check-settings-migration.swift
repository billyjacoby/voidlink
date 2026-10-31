// Run: swift BuildScripts/check-settings-migration.swift /path/to/Limelight.momd [1.0|1.1|1.2] [pinch-on|pinch-off]
// Uses a disposable store, never the app's installed database.
import CoreData
import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

guard (2...4).contains(CommandLine.arguments.count) else {
    fatalError("Pass the compiled Limelight.momd directory and optional source version")
}
let bundle = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sourceVersion = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : "1.0"
require(["1.0", "1.1", "1.2"].contains(sourceVersion), "Use an existing source model: 1.0, 1.1 or 1.2")
let legacyPinchEnabled = CommandLine.arguments.count < 4 || CommandLine.arguments[3] == "pinch-on"
guard let original = NSManagedObjectModel(contentsOf: bundle.appendingPathComponent("VoidLink v\(sourceVersion).mom")),
      let current = NSManagedObjectModel(contentsOf: bundle) else {
    fatalError("Could not load original and current models")
}
let hasAudioSetting = original.entitiesByName["Settings"]?.attributesByName["audioBufferLimitMs"] != nil
require(hasAudioSetting == (sourceVersion != "1.0"), "Source schemas must remain unchanged")
let hasGestureMode = original.entitiesByName["Settings"]?.attributesByName["trackpadGestureMode"] != nil
require(current.entitiesByName["Settings"]?.attributesByName["audioBufferLimitMs"] != nil,
        "The current model must include the audio setting")

let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("voidlink-migration-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let storeURL = directory.appendingPathComponent("test.sqlite")

func makeOriginalStore() throws {
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: original)
    let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType,
        configurationName: nil, at: storeURL)
    let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    let settings = NSManagedObject(entity: original.entitiesByName["Settings"]!, insertInto: context)
    settings.setValue("migration-test", forKey: "uniqueId")
    settings.setValue(2560, forKey: "width")
    settings.setValue(1440, forKey: "height")
    settings.setValue(5, forKey: "resolutionSelected")
    settings.setValue(true, forKey: "unlockDisplayOrientation")
    settings.setValue(legacyPinchEnabled, forKey: "enablePinch")
    if hasAudioSetting { settings.setValue(144, forKey: "audioBufferLimitMs") }
    // Explicit disabled is distinct from a legacy store with no new selection.
    if hasGestureMode { settings.setValue(0, forKey: "trackpadGestureMode") }
    let host = NSManagedObject(entity: original.entitiesByName["Host"]!, insertInto: context)
    host.setValue("Saved host", forKey: "name")
    host.setValue("saved-host-uuid", forKey: "uuid")
    let app = NSManagedObject(entity: original.entitiesByName["App"]!, insertInto: context)
    app.setValue("Saved app", forKey: "name")
    app.setValue("42", forKey: "id")
    app.setValue(true, forKey: "hidden")
    app.setValue(host, forKey: "host")
    try context.save()
    try coordinator.remove(store)
}

try makeOriginalStore()
let coordinator = NSPersistentStoreCoordinator(managedObjectModel: current)
let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType,
    configurationName: nil, at: storeURL, options: [
        NSMigratePersistentStoresAutomaticallyOption: true,
        NSInferMappingModelAutomaticallyOption: true
    ])
let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
context.persistentStoreCoordinator = coordinator
let settings = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Settings"))
require(settings.count == 1, "Saved settings must survive")
require((settings[0].value(forKey: "audioBufferLimitMs") as? NSNumber)?.intValue == (hasAudioSetting ? 144 : 80),
        "Audio preference must survive, or receive the 80 ms default")
require((settings[0].value(forKey: "width") as? NSNumber)?.intValue == 2560,
        "Custom width must survive")
require((settings[0].value(forKey: "height") as? NSNumber)?.intValue == 1440,
        "Custom height must survive")
require((settings[0].value(forKey: "resolutionSelected") as? NSNumber)?.intValue == 5,
        "Custom preset selection must survive")
require((settings[0].value(forKey: "unlockDisplayOrientation") as? NSNumber)?.boolValue == true,
        "Portrait preference must survive")
require((settings[0].value(forKey: "enablePinch") as? NSNumber)?.boolValue == legacyPinchEnabled,
        "Legacy enabled/disabled pinch preference must survive")
if current.entitiesByName["Settings"]?.attributesByName["trackpadGestureMode"] != nil {
    let rawMode = (settings[0].value(forKey: "trackpadGestureMode") as? NSNumber)?.intValue
    require(rawMode == (hasGestureMode ? 0 : -1),
            "Legacy stores must receive the unset sentinel; explicit disabled must remain disabled")
}
let apps = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "App"))
require(apps.count == 1, "Saved app must survive")
require((apps[0].value(forKey: "hidden") as? NSNumber)?.boolValue == true,
        "Hidden-app preference must survive")
let host = apps[0].value(forKey: "host") as? NSManagedObject
require(host?.value(forKey: "uuid") as? String == "saved-host-uuid",
        "Host/app relationship must survive")
try coordinator.remove(store)
print("PASS: v\(sourceVersion) → current preserves settings, hosts/apps, hidden state and pinch=\(legacyPinchEnabled)")
