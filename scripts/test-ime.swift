#!/usr/bin/env swift
// Quick test: send DNDC notifications to the running SteneoIM process.
// Run with TextEdit open and Steneo selected as input source.
// Usage: swift scripts/test-ime.swift

import Foundation

let dnc = DistributedNotificationCenter.default()

print("Sending startComposition...")
dnc.post(name: Notification.Name("com.youngpilot.Steneo.startComposition"), object: nil)
Thread.sleep(forTimeInterval: 0.2)

print("Sending updateComposition: 'Hello world'")
dnc.post(
    name: Notification.Name("com.youngpilot.Steneo.updateComposition"),
    object: nil,
    userInfo: ["text": "Hello world"]
)
Thread.sleep(forTimeInterval: 1.0)

print("Sending commitComposition: 'Hello world.'")
dnc.post(
    name: Notification.Name("com.youngpilot.Steneo.commitComposition"),
    object: nil,
    userInfo: ["text": "Hello world."]
)
Thread.sleep(forTimeInterval: 0.5)

print("Done. Check TextEdit — 'Hello world.' should have been inserted.")
