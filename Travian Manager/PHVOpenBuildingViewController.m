//
//  PHVOpenBuildingViewController.m
//  Travian Manager
//
//  Created by Matej Kramny on 01/08/2012.
//
//

#import "PHVOpenBuildingViewController.h"
#import "Building.h"
#import "Resources.h"
#import "BuildingMap.h"
#import "Storage.h"
#import "Account.h"
#import "Village.h"
#import "MBProgressHUD.h"
#import "ODRefreshControl/ODRefreshControl.h"
#import "AppDelegate.h"
#import "BuildingAction.h"
#import "PHVResearchViewController.h"

@interface PHVOpenBuildingViewController () {
	BuildingMap *buildingMap;
	Building *selectedBuilding;
	BuildingAction *selectedAction;
	NSArray *sections;
	NSArray *sectionTitles;
	NSArray *sectionFooters;
	NSArray *sectionCellTypes; // Section types
	NSIndexPath *buildActionIndexPath;
	int researchActionSection;
	MBProgressHUD *HUD;
	ODRefreshControl *refreshControl;
}

- (void)buildSections;
- (void)reloadSelectedBuilding;

@end

@implementation PHVOpenBuildingViewController
@synthesize buildings;
@synthesize otherBuildings;
@synthesize isBuildingSiteAvailableBuilding;

static NSString *rightDetailCellID = @"RightDetail";
static NSString *basicSelectableCellID = @"BasicSelectable";
static NSString *basicCellID = @"Basic";

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	
	selectedBuilding = [buildings objectAtIndex:0];
	[self buildSections];
	[self.tableView reloadData];
	[[self navigationItem] setTitle:[selectedBuilding name]];
	
	if (!isBuildingSiteAvailableBuilding)
		refreshControl = [AppDelegate addRefreshControlTo:self.tableView target:self action:@selector(didBeginRefreshing:)];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	
	refreshControl = nil;
	[[self delegate] phvOpenBuildingViewController:self didCloseBuilding:selectedBuilding];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
}

- (void)buildSections {
	NSMutableArray *secs = [[NSMutableArray alloc] init];
	NSMutableArray *titles = [[NSMutableArray alloc] init];
	NSMutableArray *footers = [[NSMutableArray alloc] init];
	NSMutableArray *types = [[NSMutableArray alloc] init];
	
	[secs addObject:[NSArray array]]; // BuildingMap section
	[titles addObject:[NSNull null]]; // no title..
	[footers addObject:@""]; // no footer..
	[types addObject:[NSNull null]]; // Never used
	
	bool buildingSite = [selectedBuilding level] == 0 && (([selectedBuilding page] & TPVillage) != 0) && !selectedBuilding.isBeingUpgraded;
	
	if (buildingSite) {
		// List available buildings
		if ([selectedBuilding availableBuildings].count > 0) {
			NSMutableArray *upgradeable = [[NSMutableArray alloc] init];
			NSMutableArray *nonupgradeable = [[NSMutableArray alloc] init];
			
			for (Building *b in selectedBuilding.availableBuildings) {
				if (b.upgradeURLString)
					[upgradeable addObject:b.name];
				else
					[nonupgradeable addObject:b.name];
			}
			
			if (upgradeable.count > 0) {
				[secs addObject:[upgradeable copy]];
				[titles addObject:@"Available Buildings"];
				[footers addObject:@"Select a building to open it."];
				[types addObject:basicSelectableCellID];
			}
			
			if (nonupgradeable.count > 0) {
				[secs addObject:[nonupgradeable copy]];
				[titles addObject:@"Unavailable Buildings"];
				[footers addObject:@"These buildings cannot be built because they have unmet requirements"];
				[types addObject:basicSelectableCellID];
			}
		} else {
			[secs addObject:@"No buildings available"];
			[titles addObject:@"Buildings"];
			[footers addObject:@""];
			[types addObject:basicCellID];
		}
	} else {
		// Details
		[secs addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%d", [selectedBuilding level]], @"Level", nil]]; // level
		[titles addObject:@"Details"];
		[footers addObject:selectedBuilding.description != nil ? selectedBuilding.description : @""];
		[types addObject:rightDetailCellID];
		
		// Properties
		if ([[selectedBuilding properties] count] > 0) {
			[secs addObject:[selectedBuilding properties]];
			[titles addObject:@"Properties"];
			[footers addObject:@""];
			[types addObject:rightDetailCellID];
		}
		
		// Resources
		if ([selectedBuilding resources]) {
			Resources *res = [selectedBuilding resources];
			[secs addObject:@{ @"Wood" : [NSString stringWithFormat:@"%d", (int)res.wood],
			 @"Clay" : [NSString stringWithFormat:@"%d", (int)res.clay],
			 @"Iron" : [NSString stringWithFormat:@"%d", (int)res.iron],
			 @"Wheat" : [NSString stringWithFormat:@"%d", (int)res.wheat]
			 }];
			
			if (isBuildingSiteAvailableBuilding)
				[titles addObject:NSLocalizedString(@"Resources required build", @"Resources required to build")];
			else
				[titles addObject:NSLocalizedString(@"Resources required", @"Resources required to upgrade building to next level")];
			
			if ([[selectedBuilding.parent resources] hasMoreResourcesThanResource:selectedBuilding.resources])
				[footers addObject:@"You have enough resources"];
			else
				[footers addObject:@"You do not have enough resources"];
			
			[types addObject:rightDetailCellID];
		}
		
		// Conditions
		if ([[selectedBuilding buildConditionsDone] count] > 0) {
			[secs addObject:selectedBuilding.buildConditionsDone];
			[titles addObject:@"Accomplished build conditions"];
			[footers addObject:@""];
			[types addObject:basicCellID];
		}
		if ([[selectedBuilding buildConditionsError] count] > 0) {
			[secs addObject:selectedBuilding.buildConditionsError];
			[titles addObject:@"Build conditions"];
			[footers addObject:@"Upgrade buildings listed in order to build"];
			[types addObject:basicCellID];
		}
		if ([selectedBuilding cannotBuildReason] != nil) {
			[secs addObject:selectedBuilding.cannotBuildReason];
			[titles addObject:@"Cannot build"];
			[footers addObject:@""];
			[types addObject:basicCellID];
		}
		
		// Actions
		if ([[selectedBuilding actions] count] > 0) {
			NSMutableArray *strings = [[NSMutableArray alloc] initWithCapacity:[selectedBuilding.actions count]];
			for (BuildingAction *action in selectedBuilding.actions) {
				[strings addObject:action.name];
			}
			
			[secs addObject:strings];
			[titles addObject:@"Research"];
			[footers addObject:@""];
			[types addObject:basicSelectableCellID];
			
			researchActionSection = [secs count]-1;
		}
		
		// Buttons
		if ([[selectedBuilding buildConditionsError] count] == 0 && ![selectedBuilding cannotBuildReason]) {
			if (isBuildingSiteAvailableBuilding) {
				if (selectedBuilding.upgradeURLString) {
					[secs addObject:[NSString stringWithFormat:NSLocalizedString(@"Build", @"Build building site object"), selectedBuilding.name]];
					[titles addObject:@"Build"];
					[footers addObject:@""];
					[types addObject:basicSelectableCellID];
					buildActionIndexPath = [NSIndexPath indexPathForRow:0 inSection:[secs count]-1];
				}
			} else {
				// Upgrade button
				[secs addObject:[NSString stringWithFormat:@"Upgrade to level %d", [selectedBuilding level]+1]];
				[titles addObject:@"Actions"];
				[footers addObject:@""];
				[types addObject:basicSelectableCellID];
				buildActionIndexPath = [NSIndexPath indexPathForRow:0 inSection:[secs count]-1];
			}
		}
	}
	
	sections = [secs copy];
	sectionTitles = [titles copy];
	sectionFooters = [footers copy];
	sectionCellTypes = [types copy];
}

- (void)reloadSelectedBuilding {
	[selectedBuilding addObserver:self forKeyPath:@"finishedLoading" options:NSKeyValueObservingOptionNew context:nil];
	[selectedBuilding fetchDescription];
	
	HUD = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
	HUD.labelText = @"Loading";
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
	if ([segue.identifier isEqualToString:@"OpenResearch"]) {
		PHVResearchViewController *rvc = segue.destinationViewController;
		rvc.action = selectedAction;
	}
}

#pragma mark refreshControl did begin refreshing

- (void)didBeginRefreshing:(id)sender {
	[self reloadSelectedBuilding];
	[refreshControl endRefreshing];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return [sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	id sec = [sections objectAtIndex:section];
	
	if ([sec isKindOfClass:[NSString class]])
		return 1;
	
    return [sec count];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	id sec = [sections objectAtIndex:indexPath.section];
	
	UITableViewCell *cell;
	if ([sec isKindOfClass:[NSString class]]) {
		cell = [tableView dequeueReusableCellWithIdentifier:[sectionCellTypes objectAtIndex:indexPath.section]];
		cell.textLabel.text = sec;
	} else if ([sec isKindOfClass:[NSArray class]]) {
		cell = [tableView dequeueReusableCellWithIdentifier:[sectionCellTypes objectAtIndex:indexPath.section]];
		cell.textLabel.text = [sec objectAtIndex:indexPath.row];
	} else {
		cell = [tableView dequeueReusableCellWithIdentifier:[sectionCellTypes objectAtIndex:indexPath.section]];
		NSString *key = [[(NSDictionary *)sec allKeys] objectAtIndex:indexPath.row];
		cell.textLabel.text = key;
		cell.detailTextLabel.text = [(NSDictionary *)sec objectForKey:key];
	}
	
	return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return [sectionTitles objectAtIndex:section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return [sectionFooters objectAtIndex:section];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (section == 0) {
		if (!buildingMap) {
			buildingMap = [[BuildingMap alloc] initWithBuildings:buildings hideBuildings:otherBuildings];
			
			buildingMap.delegate = self;
			buildingMap.backgroundColor = [UIColor clearColor];
		}
		
		return buildingMap;
	}
	
	return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	if (section == 0)
		return 185.0f;
	
	return 44.0f;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (selectedBuilding.level == 0 && selectedBuilding.page & TPVillage && !isBuildingSiteAvailableBuilding) {
		// Building site. Click to first or second section opens a building
		UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MainStoryboard_iPhone" bundle:nil];
		PHVOpenBuildingViewController *ob = (PHVOpenBuildingViewController *)[storyboard instantiateViewControllerWithIdentifier:@"openBuildingView"];
		
		ob.delegate = self;
		
		Building *building;
		NSString *name = [[sections objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];
		for (Building *b in selectedBuilding.availableBuildings) {
			if ([b.name isEqualToString:name]) {
				building = b;
				break;
			}
		}
		
		if (!building) return;
		
		building.coordinates = selectedBuilding.coordinates;
		ob.buildings = @[ building ];
		
		NSMutableArray *others = [[NSMutableArray alloc] initWithArray:otherBuildings];
		others = [[others arrayByAddingObjectsFromArray:buildings] mutableCopy];
		[others removeObjectIdenticalTo:selectedBuilding];
		
		ob.otherBuildings = others;
		ob.isBuildingSiteAvailableBuilding = YES;
		
		[[self navigationController] pushViewController:ob animated:YES];
	} else if ([indexPath compare:buildActionIndexPath] == NSOrderedSame) {
		// Build
		[[self delegate] phvOpenBuildingViewController:self didBuildBuilding:selectedBuilding];
		
		[[self navigationController] popViewControllerAnimated:YES];
	} else if (researchActionSection > 0 && indexPath.section == researchActionSection) {
		// Push view controller for research
		selectedAction = [[selectedBuilding actions] objectAtIndex:indexPath.row];
		[self performSegueWithIdentifier:@"OpenResearch" sender:self];
	}
}

#pragma mark - BuildingMapDelegate

- (void)buildingMapSelectedIndexOfBuilding:(NSInteger)index {
	selectedBuilding = [buildings objectAtIndex:index];
	bool buildingSite = selectedBuilding.level == 0 && selectedBuilding.page & TPVillage && !selectedBuilding.isBeingUpgraded;
	if ((buildingSite && !selectedBuilding.availableBuildings) || (!buildingSite && ![selectedBuilding description])) {
		// Fetch
		[self reloadSelectedBuilding];
		
		return;
	}
	
	[self buildSections];
	[self.tableView reloadData];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if (object == selectedBuilding && [keyPath isEqualToString:@"finishedLoading"]) {
		[selectedBuilding removeObserver:self forKeyPath:@"finishedLoading"];
		[self buildSections];
		[self.tableView reloadData];
		[HUD hide:YES];
	}
}

#pragma mark - PHVOpenBuildingDelegate

- (void)phvOpenBuildingViewController:(PHVOpenBuildingViewController *)controller didBuildBuilding:(Building *)building {
	[building buildFromURL:[[Storage sharedStorage].account urlForString:building.upgradeURLString]];
}

- (void)phvOpenBuildingViewController:(PHVOpenBuildingViewController *)controller didCloseBuilding:(Building *)building {
	
}

@end
