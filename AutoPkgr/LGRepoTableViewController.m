//
//  LGRepoTableViewController.m
//  AutoPkgr
//
//  Created by Eldon Ahrold on 6/3/2015.
//
//  Copyright 2015 Eldon Ahrold
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "LGRepoTableViewController.h"
#import "LGTableCellViews.h"
#import "LGAutoPkgr.h"
#import "LGRecipeSearch.h"
#import "LGAutoPkgRepo.h"
#import "LGAutoPkgTask.h"
#import "LGGitHubJSONLoader.h"

@interface LGRepoTableViewController ()

@property (copy, nonatomic) NSArray *repos;
@property (copy, nonatomic) NSMutableArray *searchedRepos;

@property (weak) IBOutlet LGTableView *popularRepositoriesTableView;
@property (weak) IBOutlet NSSearchField *repoSearch;

@end

@implementation LGRepoTableViewController {
    LGRecipeSearch *_searchPanel;

    BOOL _awake;
    BOOL _updateRepoInternally;
    BOOL _fetchingRepoData;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib
{
    if (!_awake) {
        _awake = YES;
        [_repoSearch setTarget:self];
        [_repoSearch setAction:@selector(executeRepoSearch:)];

        [self reload];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:kLGNotificationReposModified object:nil];
    }
}

- (void)reload
{
    if (!_updateRepoInternally) {
        _fetchingRepoData = YES;
        [LGAutoPkgRepo commonRepos:^(NSArray *repos) {
            NSArray *sortDescriptors = nil;
            if (_popularRepositoriesTableView.sortDescriptors.count) {
                sortDescriptors = _popularRepositoriesTableView.sortDescriptors;
            } else {
                sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(stars))
                                                                  ascending:NO]];
            }

            _repos = [repos sortedArrayUsingDescriptors:sortDescriptors];
            _fetchingRepoData = NO;
            [self executeRepoSearch:nil];
        }];
    }
    _updateRepoInternally = NO;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return _fetchingRepoData ? 1 : _searchedRepos.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if (_fetchingRepoData) {
        LGRepoStatusCellView *statusCell = nil;
        if ([tableColumn.identifier isEqualToString:NSStringFromSelector(@selector(cloneURL))]) {
            statusCell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];

            statusCell.textField.stringValue = @"Fetching remote data...";

        } else if ([[tableColumn identifier] isEqualToString:@"status"]) {
            statusCell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];

            [statusCell.progressIndicator startAnimation:self];
        }
        return statusCell;
    }

    LGAutoPkgRepo *repo = [_searchedRepos objectAtIndex:row];
    LGRepoStatusCellView *statusCell = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];

    if ([[tableColumn identifier] isEqualToString:NSStringFromSelector(@selector(isInstalled))]) {
        statusCell.enabledCheckBox.state = repo.isInstalled;
        statusCell.enabledCheckBox.tag = row;
        statusCell.enabledCheckBox.action = @selector(enableRepo:);
        statusCell.enabledCheckBox.target = self;

    } else if ([[tableColumn identifier] isEqualToString:NSStringFromSelector(@selector(cloneURL))]) {
        statusCell.textField.stringValue = repo.cloneURL.absoluteString;
    } else if ([[tableColumn identifier] isEqualToString:NSStringFromSelector(@selector(stars))]) {
        if (repo.homeURL && (repo.stars > 0)) {
            // u2650 is the star symbol.
            statusCell.textField.stringValue = [@"\u2605 " stringByAppendingString:@(repo.stars).stringValue];
        } else {
            statusCell.textField.stringValue = @"";
        }
    } else if ([[tableColumn identifier] isEqualToString:@"status"]) {
        statusCell.imageView.hidden = YES;
        repo.statusChangeBlock = ^(LGAutoPkgRepoStatus status) {
            switch (status) {
                case kLGAutoPkgRepoNotInstalled: {
                    statusCell.imageView.hidden = YES;
                    break;
                }
                case kLGAutoPkgRepoUpdateAvailable: {
                    statusCell.imageView.image = [NSImage LGStatusUpdateAvailable];
                    statusCell.imageView.hidden = NO;
                    break;
                }
                case kLGAutoPkgRepoUpToDate: {
                    statusCell.imageView.image = [NSImage LGStatusUpToDate];
                    statusCell.imageView.hidden = NO;
                    break;
                }
            }
            [statusCell.progressIndicator stopAnimation:self];
        };

        if (repo.isInstalled) {
            [statusCell.progressIndicator startAnimation:self];
            statusCell.imageView.image = [NSImage LGStatusUpdateAvailable];
        }
        // Calling checkRepoStatus will execute the repo.statusChangeBlock.
        [repo checkRepoStatus:nil];
    }
    return statusCell;
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    [_searchedRepos sortUsingDescriptors:tableView.sortDescriptors];
    [tableView reloadData];
}

- (void)enableRepo:(NSButton *)sender
{
    _updateRepoInternally = YES;

    /* The button's tag is set to the row in 
     * the tableView:viewForTableColumn:row: */
    NSInteger row = sender.tag;
    BOOL add = sender.state;

    LGAutoPkgRepo *repo = _searchedRepos[row];

    void (^repoModified)(NSError * error) = ^void(NSError *error) {
        [_progressDelegate stopProgress:error];
        if (error) {
            sender.state = !sender.state;
        }
    };

    NSString *message = [NSString stringWithFormat:@"%@ %@", add ? @"Adding" : @"Removing", repo.cloneURL];

    NSLog(@"%@", message);
    [_progressDelegate startProgressWithMessage:message];
    if (add) {
        [repo install:^(NSError *error) {
            repoModified(error);
        }];
    } else {
        [repo remove:^(NSError *error) {
            repoModified(error);
        }];
    }
}

- (void)updateRepo:(id)sender
{
    _updateRepoInternally = YES;
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        LGAutoPkgRepo *repo = [sender representedObject];
        NSString *message = [NSString stringWithFormat:@"Updating %@", repo.cloneURL];

        [_progressDelegate startProgressWithMessage:message];
        [repo updateRepo:^(NSError *error) {
            [_progressDelegate stopProgress:error];
        }];
    }
}

- (void)executeRepoSearch:(id)sender
{
    [_popularRepositoriesTableView beginUpdates];

    [_popularRepositoriesTableView removeRowsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _popularRepositoriesTableView.numberOfRows)] withAnimation:NSTableViewAnimationEffectNone];

    if (_repoSearch.stringValue.length == 0) {
        _searchedRepos = [_repos mutableCopy];
    } else {
        NSPredicate *searchPredicate = [NSPredicate predicateWithFormat:@"%K.absoluteString CONTAINS[CD] %@", NSStringFromSelector(@selector(cloneURL)), _repoSearch.stringValue];
        _searchedRepos = [[_repos filteredArrayUsingPredicate:searchPredicate] mutableCopy];
    }

    [_popularRepositoriesTableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _searchedRepos.count)] withAnimation:NSTableViewAnimationEffectNone];
    [_popularRepositoriesTableView endUpdates];
}

- (NSMenu *)contextualMenuForRow:(NSInteger)row
{

    LGAutoPkgRepo *repo = _searchedRepos[row];
    NSMenu *menu = [[NSMenu alloc] init];

    // Update Repo...
    NSMenuItem *updateItem = [[NSMenuItem alloc] initWithTitle:@"Update Repo"
                                                        action:@selector(updateRepo:)
                                                 keyEquivalent:@""];
    updateItem.target = self;
    updateItem.representedObject = repo;

    [menu addItem:updateItem];

    // Commits ...
    if (repo.commitsURL) {
        NSMenuItem *commitsItem = [[NSMenuItem alloc] initWithTitle:@"Open Commits Page"
                                                             action:@selector(viewCommitsOnGitHub:)
                                                      keyEquivalent:@""];
        commitsItem.target = repo;
        [menu addItem:commitsItem];
    }

    if (repo.cloneURL) {
        NSMenuItem *cloneItem = [[NSMenuItem alloc] initWithTitle:@"Copy url to clipboard"
                                                           action:@selector(copyToPasteboard:)
                                                    keyEquivalent:@""];

        cloneItem.representedObject = repo.cloneURL.absoluteString;
        cloneItem.target = self;
        [menu addItem:cloneItem];
    }

    if (repo.path) {
        NSMenuItem *clipboardItem = [[NSMenuItem alloc] initWithTitle:@"Copy path to clipboard"
                                                               action:@selector(copyToPasteboard:)
                                                        keyEquivalent:@""];
        clipboardItem.representedObject = repo.path;
        clipboardItem.target = self;
        [menu addItem:clipboardItem];

        NSMenuItem *resetItem = [[NSMenuItem alloc] init];
        // Reset repo menu itme

        NSMutableAttributedString *str = [[NSMutableAttributedString alloc] initWithString:@"\u26A0 Hard Reset Repo \u26A0"];
        NSRange range = NSMakeRange(0, str.length);
        [str addAttributes:@{ NSForegroundColorAttributeName : [NSColor redColor],
                              NSFontAttributeName : [NSFont systemFontOfSize:14]
        }
                     range:range];

        resetItem.attributedTitle = str;

        resetItem.action = @selector(hardResetToOriginMaster);
        resetItem.target = repo;
        [menu addItem:resetItem];
    }

    return menu;
}

- (void)copyToPasteboard:(id)sender
{
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        NSString *string = [sender representedObject];
        [[NSPasteboard generalPasteboard] declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
        [[NSPasteboard generalPasteboard] setString:string forType:NSStringPboardType];
    }
}

#pragma mark - Search Panel
- (IBAction)openSearchPanel:(id)sender
{
    if (!_searchPanel) {
        _searchPanel = [[LGRecipeSearch alloc] init];
    }

    [NSApp beginSheet:_searchPanel.window
        modalForWindow:self.modalWindow
         modalDelegate:self
        didEndSelector:@selector(didCloseSearchPanel)
           contextInfo:NULL];
}

- (void)didCloseSearchPanel
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [_searchPanel.window close];
        _searchPanel = nil;
    }];
}

@end
