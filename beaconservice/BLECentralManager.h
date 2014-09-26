//
//  BLECentralManager.h
//  beaconservice
//
//  Created by Sam Wang on 9/26/14.
//  Copyright (c) 2014 Sam Wang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>

@interface BLECentralManager : NSObject<CBCentralManagerDelegate, CBPeripheralDelegate, CLLocationManagerDelegate, CBPeripheralManagerDelegate> {
    
}

@property (strong, nonatomic) CBCentralManager      *centralManager;
@property (strong, nonatomic) CBPeripheral          *discoveredPeripheral;
@property (strong, nonatomic) NSMutableData         *data;
@property (nonatomic, retain) CLBeaconRegion        *beaconRegion;
@property (nonatomic, retain) CBPeripheralManager   *peripheralManager;
@property (strong, nonatomic) CLLocationManager     *locationManager;

+ (BLECentralManager *) getInstance;
- (void)registerBeaconRegionWithUUID;

@end
