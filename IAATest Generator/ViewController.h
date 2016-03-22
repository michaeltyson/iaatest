//
//  ViewController.h
//  IAATest
//
//  Created by Michael Tyson on 23/10/2013.
//  Copyright (c) 2013 A Tasty Pixel. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController
- (IBAction)switchOscillator:(UISwitch *)sender;
@property (strong, nonatomic) IBOutlet UISwitch *oscillatorSwitch;
@end
