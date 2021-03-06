//
//  CreateViewController.m
//  Wayfarer
//
//  Created by Chloe on 2016-02-08.
//  Copyright © 2016 Chloe Horgan. All rights reserved.
//

#import <Photos/Photos.h>
#import <MapKit/MapKit.h>
#import "UIImage+fixOrientation.h"
#import "CreateViewController.h"
#import "CreateTableViewCell.h"
#import "Photo.h"
#import "Entry.h"

@interface CreateViewController () <UITableViewDelegate, UITableViewDataSource, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (strong, nonatomic) NSMutableDictionary *locationDictionary;
@property (strong, nonatomic) PHFetchResult *fetchResult;
@property (weak, nonatomic) IBOutlet UITableView *createTableView;
@property (strong, nonatomic) NSMutableArray *photosArray;
@property (strong, nonatomic) NSDate *requestDate;
@property (strong, nonatomic) UIImagePickerController *imagePicker;
@property (assign, nonatomic) CGPoint hitPoint;
@property (strong, nonatomic) UITextView *activeView;

@end

@implementation CreateViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    //TODAYS DATE
    self.requestDate = [[NSCalendar currentCalendar] startOfDayForDate:[NSDate date]];
    
    
    //TESTING DATE
//    NSDateComponents *comps = [[NSDateComponents alloc] init];
//    [comps setDay:20];
//    [comps setMonth:10];
//    [comps setYear:2015];
//    NSDate *test = [[NSCalendar currentCalendar] dateFromComponents:comps];
//    self.requestDate = [[NSCalendar currentCalendar] startOfDayForDate:test];
    
    self.createTableView.delegate = self;
    self.createTableView.dataSource = self;
    
    self.locationDictionary = [[NSMutableDictionary alloc] init];
    self.photosArray = [[NSMutableArray alloc] init];
    [self.locationDictionary removeAllObjects];
    [self.photosArray removeAllObjects];
    
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusAuthorized) {
        // Authorized
        [self imageRequest];
    } else if (status == PHAuthorizationStatusDenied) {
        // Pop-up, need authorization
        [self showNoPermissionAlert];
    } else if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            if (status == PHAuthorizationStatusAuthorized) {
                // Authorized
                [self imageRequest];
            } else {
                // Pop-up, need authorization
                [self showNoPermissionAlert];
            }
        }];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [self.createTableView reloadData];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Save Button/Realm saving

- (IBAction)saveEntry:(id)sender {
    if (self.photosArray.count != 0) {
        Entry *newEntry = [[Entry alloc] init];
        newEntry.date = self.requestDate;
        RLMRealm *realm = [RLMRealm defaultRealm];
        [realm beginWriteTransaction];
        for (Photo *photo in self.photosArray) {
            photo.entry = newEntry;
            [newEntry.photos addObject:photo];
            [realm addObject:photo];
        }
        [realm addObject:newEntry];
        [realm commitWriteTransaction];
        [self.navigationController popToRootViewControllerAnimated:YES];
    } else {
        [self showNoPhotosAlert];
    }
}


#pragma mark - Table View methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.locationDictionary.allKeys.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CreateTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CreateCell" forIndexPath:indexPath];
    [self configureCell:cell forIndexPath:indexPath];
    return cell;
}

- (void)configureCell:(CreateTableViewCell *)cell forIndexPath:(NSIndexPath *)indexPath {
    cell.photo = self.photosArray[indexPath.row];

    cell.photoView.image = [UIImage imageWithData:cell.photo.photo];
    cell.textView.text = cell.photo.location;
}

#pragma mark - Retrieving image/location methods

- (void)imageRequest {
    // Check if there is permission
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied) {
        [self showNoPermissionAlert];
    }
    NSLog(@"after possibly having shown the permissions alert");
    //Fetch todays photos
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"creationDate >= %@ AND creationDate < %@", self.requestDate, [self.requestDate dateByAddingTimeInterval:60*60*48]];
    self.fetchResult = [PHAsset fetchAssetsWithOptions:fetchOptions];
    NSLog(@"after starting the fetch");
    NSLog(@"%i", self.fetchResult.count);
    if (self.fetchResult.count < 1) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showNoPhotosAlert];
        });
    }
    
    //Get image data
    PHImageManager *imageManager = [[PHImageManager alloc] init];
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
    
    for (PHAsset *asset in self.fetchResult) {
        [imageManager requestImageDataForAsset:asset options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
            //     [self geoCoder:asset withImage:imageData];
            NSArray *inputArray = @[asset, imageData];
            [self performSelector:@selector(locationSort:) withObject:inputArray afterDelay:1.5];
        }];
    }
}

- (void)locationSort:(NSArray *)inputArray {
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    PHAsset *asset = inputArray[0];
    NSData *imageData = inputArray[1];
    NSString *defaultLocationName = @"Unknown Location";
    
    if (asset.location) {
        CreateViewController * __weak weakSelf = self;
        [geocoder reverseGeocodeLocation:asset.location completionHandler:^(NSArray<CLPlacemark *> * _Nullable placemarks, NSError * _Nullable error) {
            
            if (error) {
                NSLog(@"%@", error);
            } else {
                // Sorting into locationDictionary
                if (placemarks[0].subLocality) {
                    [weakSelf addPhotoWithImageData:imageData location:placemarks[0].subLocality];
                } else {
                    [weakSelf addPhotoWithImageData:imageData location:defaultLocationName];
                }
            }
        }];
    } else {
        [self addPhotoWithImageData:imageData location:defaultLocationName];
    }
}

- (void)addPhotoWithImageData:(NSData *)imageData location:(NSString *)location {
    if (![self.locationDictionary objectForKey:location]) {
        [self.locationDictionary setObject:[[NSMutableArray alloc] init] forKey:location];
    }
    NSMutableArray *images = [self.locationDictionary valueForKey:location];
    
    Photo *photo = [[Photo alloc] init];
    photo.location = location;
    photo.photo = imageData;
    if (images.count == 0) {
        [self.photosArray addObject:photo];
    }
    [images addObject:photo];
    [self.createTableView reloadData];

}

#pragma mark - Image Picker

- (IBAction)swapButton:(id)sender {
    self.hitPoint = [sender convertPoint:CGPointZero toView:self.createTableView];
    self.imagePicker = [[UIImagePickerController alloc] init];
    self.imagePicker.delegate = self;
    self.imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    [self presentViewController:self.imagePicker animated:YES completion:nil];
}


- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self.imagePicker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
    NSIndexPath *indexPath = [self.createTableView indexPathForRowAtPoint:self.hitPoint];
    CreateTableViewCell *cell = (CreateTableViewCell *)[self.createTableView cellForRowAtIndexPath:indexPath];
    UIImage *pickedImage = [info objectForKey:UIImagePickerControllerOriginalImage];
    [pickedImage fixOrientation];
    NSData *newImage = [NSData dataWithData:UIImageJPEGRepresentation(pickedImage, 1.0)];
    cell.photo.photo = newImage;
    [self.imagePicker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Alert

- (void)showNoPhotosAlert {
    UIAlertController *noPhotosAlert = [UIAlertController alertControllerWithTitle:@"No Photos!" message:@"You need to take some photos today in order to create an entry." preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
    }];
    
    [noPhotosAlert addAction:defaultAction];
    [self presentViewController:noPhotosAlert animated:YES completion:nil];

}

- (void)showNoPermissionAlert {
    UIAlertController *noPermissionAlert = [UIAlertController alertControllerWithTitle:@"Permission Denied" message:@"You need to allow Photos permission to create an entry." preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
    }];
    
    [noPermissionAlert addAction:defaultAction];
    [self presentViewController:noPermissionAlert animated:YES completion:nil];
    
}


@end
