//
//  BLECentralManager.m
//  beaconservice
//
//  Created by Sam Wang on 9/26/14.
//  Copyright (c) 2014 Sam Wang. All rights reserved.
//

#import "BLECentralManager.h"

@implementation BLECentralManager

static BLECentralManager *centralManager;

+ (BLECentralManager *) getInstance {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        centralManager = [[BLECentralManager alloc] init];
    });
    
    return centralManager;
}

- (void)registerBeaconRegionWithUUID {
    
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    
    // Check for iOS 8. Without this guard the code will crash with "unknown selector" on iOS 7.
    [self.locationManager requestAlwaysAuthorization];
    
    // Create the beacon region to be monitored.
    CLBeaconRegion *region = [[CLBeaconRegion alloc] initWithProximityUUID:[[NSUUID alloc] initWithUUIDString:@"E2C56DB5-DFFB-48D2-B060-D0F5A71096E0"] identifier: @"region1"];
    region.notifyEntryStateOnDisplay = YES;
    region.notifyOnEntry = YES;
    region.notifyOnExit = YES;
    [_locationManager startMonitoringForRegion:region];
    [_locationManager stopRangingBeaconsInRegion:region];
}

#pragma mark - Central Methods

/** centralManagerDidUpdateState is a required protocol method.
 *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
 *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
 *  the Central is ready to be used.
 */
- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state != CBCentralManagerStatePoweredOn) {
        // In a real app, you'd deal with all the states correctly
        return;
    }
    
    // The state must be CBCentralManagerStatePoweredOn...
    [self scan];
}


/** Scan for peripherals - specifically for our service's 128bit CBUUID
 */
- (void)scan
{
    [self.centralManager scanForPeripheralsWithServices:nil
                                                options:@{ CBCentralManagerScanOptionAllowDuplicatesKey:@YES }];
    NSLog(@"Scanning started");
}


/** This callback comes whenever a peripheral that is advertising the TRANSFER_SERVICE_UUID is discovered.
 *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
 *  we start the connection process
 */
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    // Ok, it's in range - have we already seen it?
    NSLog(@"test - Discovered %@ at %@, identifier = %@, advertisementData=%@",
          peripheral.name, RSSI, peripheral.identifier, advertisementData);
}


/** If the connection fails for whatever reason, we need to deal with it.
 */
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Failed to connect to %@. (%@)", peripheral, [error localizedDescription]);
    [self cleanup];
}


/** We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
 */
- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Peripheral Connected");
    
    // Stop scanning
    [self.centralManager stopScan];
    NSLog(@"Scanning stopped");
    
    // Clear the data that we may already have
    [self.data setLength:0];
    
    // Make sure we get the discovery callbacks
    peripheral.delegate = self;
    
    // Search only for services that match our UUID
    [peripheral discoverServices:nil];
}


/** The Transfer Service was discovered
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering services: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    
    // Discover the characteristic we want...
    
    // Loop through the newly filled peripheral.services array, just in case there's more than one.
    for (CBService *service in peripheral.services) {
        NSLog(@"discovered services: %@", service);
        [peripheral discoverCharacteristics:nil forService:service];
    }
}


/** The Transfer characteristic was discovered.
 *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
 */
- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    // Deal with errors (if any)
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        [self cleanup];
        return;
    }
    
    // Again, we loop through the array, just in case.
    for (CBCharacteristic *characteristic in service.characteristics) {
        // And check if it's the right one
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@"AA90"]]) {
            NSLog(@"AA90 - Write");
            unsigned char bytes[] = { 0x05 };
            NSData* expectedData = [NSData dataWithBytes:bytes length:sizeof(bytes)];
            [peripheral writeValue:expectedData forCharacteristic:characteristic type:CBCharacteristicWriteWithoutResponse];
        }else if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:@"AA91"]]) {
            NSLog(@"AA91 - Read");
            [peripheral readValueForCharacteristic:characteristic];
        }
    }
    
    // Once this is complete, we just need to wait for the data to come in.
}



#pragma - mark: done subscribe and waiting for callback

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error writing characteristics: %@", [error localizedDescription]);
        return;
    }
    
    NSString *stringFromData = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
    
    // Log it
    NSLog(@"Received: %@", stringFromData);
    
    // Otherwise, just add the data on to what we already have
    [self.data appendData:characteristic.value];
    
    [peripheral setNotifyValue:NO forCharacteristic:characteristic];
    [self.centralManager cancelPeripheralConnection:peripheral];
}

/** This callback lets us know more data has arrived via notification on the characteristic
 */
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error discovering characteristics: %@", [error localizedDescription]);
        return;
    }
    
    NSString *stringFromData = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
    
    // Log it
    NSLog(@"Received: %@", stringFromData);
    
    // Otherwise, just add the data on to what we already have
    [self.data appendData:characteristic.value];
    [peripheral setNotifyValue:NO forCharacteristic:characteristic];
}


/** The peripheral letting us know whether our subscribe/unsubscribe happened or not
 */
- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error) {
        NSLog(@"Error changing notification state: %@", error.localizedDescription);
    }
    
    // Notification has started
    if (characteristic.isNotifying) {
        NSLog(@"Notification began on %@", characteristic);
    }
    
    // Notification has stopped
    else {
        // so disconnect from the peripheral
        NSLog(@"Notification stopped on %@.  Disconnecting", characteristic);
        [self.centralManager cancelPeripheralConnection:peripheral];
    }
}


/** Once the disconnection happens, we need to clean up our local copy of the peripheral
 */
- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Peripheral Disconnected");
    self.discoveredPeripheral = nil;
    // We're disconnected, so start scanning again
    [self scan];
}


/** Call this when things either go wrong, or you're done with the connection.
 *  This cancels any subscriptions if there are any, or straight disconnects if not.
 *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
 */
- (void)cleanup
{
    // Don't do anything if we're not connected
    if (!self.discoveredPeripheral.state == CBPeripheralStateConnected) {
        return;
    }
    
    // See if we are subscribed to a characteristic on the peripheral
    if (self.discoveredPeripheral.services != nil) {
        for (CBService *service in self.discoveredPeripheral.services) {
            if (service.characteristics != nil) {
                for (CBCharacteristic *characteristic in service.characteristics) {
                    //if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:TRANSFER_CHARACTERISTIC_UUID]]) {
                    if (characteristic.isNotifying) {
                        // It is notifying, so unsubscribe
                        [self.discoveredPeripheral setNotifyValue:NO forCharacteristic:characteristic];
                        
                        // And we're done.
                        return;
                    }
                    //}
                }
            }
        }
    }
    
    // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
    [self.centralManager cancelPeripheralConnection:self.discoveredPeripheral];
}

#pragma - mark CLLocationManagerDelegate

- (void) locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region{
    CLBeacon *beacon = [beacons objectAtIndex:0];
    
    for(int i = 0; i < [beacons count]; i++){
        CLBeacon *tmpBeacon = [beacons objectAtIndex:i];
        NSLog(@"beacon=%@", tmpBeacon);
        NSString *beaconInfo = [NSString stringWithFormat:@"%@", tmpBeacon];
        NSString *range = [[[[beaconInfo componentsSeparatedByString:@"+/- "] objectAtIndex:1] componentsSeparatedByString:@"m"] objectAtIndex:0];
        double meter = [range doubleValue];
        NSLog(@"meter, %f", meter);
    }
    
    switch (beacon.proximity) {
        case CLProximityImmediate:
            break;
        case CLProximityNear:
            break;
        case CLProximityFar:
            break;
        default:
            break;
    }
}

- (void) locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
    //NSLog(@"didDetermineState, state=%ld", state);
    switch (state) {
        case CLRegionStateInside:
            /* it would be smart to start ranging beacons here */
            [manager startRangingBeaconsInRegion:(CLBeaconRegion *)region];
            break;
        case CLRegionStateOutside:
        case CLRegionStateUnknown:
        default:
            /* beacons will typically be on a low refresh */
            /* so they will probably flip flop a bit when you are in range */
            /* I would advise to stop ranging on a timer */
            NSLog(@"Region unknown");
    }
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
    NSLog(@"%s", __func__);
    
    if(error){
        NSString *message = [error localizedDescription];
        NSLog(@"%@", message);
    }
}

- (void) locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    NSLog(@"didEnterRegion");
    if ([region isKindOfClass:[CLBeaconRegion class]]) {
        [manager startRangingBeaconsInRegion:(CLBeaconRegion *)region];
    }
}

- (void) didExitRegion:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    NSLog(@"didExitRegion");
    if ([region isKindOfClass:[CLBeaconRegion class]]) {
        [manager stopMonitoringForRegion:region];
    }
}
- (void) locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region {
    NSLog(@"didStartMonitoringForRegion");
    [_locationManager requestStateForRegion:region];
}

- (void) locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations{
    NSLog(@"didUpdateLocations");
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    if (![CLLocationManager locationServicesEnabled]) {
        NSLog(@"Couldn't turn on ranging: Location services are not enabled.");
    }
    
    if ([CLLocationManager authorizationStatus] != kCLAuthorizationStatusAuthorizedAlways) {
        NSLog(@"Couldn't turn on monitoring: Location services not authorised.");
    }
}

#pragma - mark CBPeripheralManagerDelegate
- (void) peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral {
}


@end
