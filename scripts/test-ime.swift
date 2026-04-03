#!/usr/bin/env swift
// Quick test: send DNDC notifications to the running TalkmanIM process.
// Run with TextEdit open and Talkman selected as input source.
// Usage: swift scripts/test-ime.swift

import Foundation

let dnc = DistributedNotificationCenter.default()

print("Sending startComposition...")
dnc.post(name: Notification.Name("com.youngpilot.Talkman.startComposition"), object: nil)
Thread.sleep(forTimeInterval: 0.2)

print("Sending updateComposition: 'Hello world'")
dnc.post(
    name: Notification.Name("com.youngpilot.Talkman.updateComposition"),
    object: nil,
    userInfo: ["text": "Hello world"]
)
Thread.sleep(forTimeInterval: 1.0)

print("Sending commitComposition: 'Hello world.'")
dnc.post(
    name: Notification.Name("com.youngpilot.Talkman.commitComposition"),
    object: nil,
    userInfo: ["text": "Hello world."]
)
Thread.sleep(forTimeInterval: 0.5)

print("Done. Check TextEdit — 'Hello world.' should have been inserted.")
