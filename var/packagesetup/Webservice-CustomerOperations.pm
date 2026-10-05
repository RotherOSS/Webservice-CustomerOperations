# --
# var/packagesetup/Webservice-CustomerOperations.pm - code to excecute during package installation
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package var::packagesetup::Webservice-CustomerOperations;

use strict;
use warnings;

use utf8;

use List::Util qw(first);
use File::Basename;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = qw(
    Kernel::Config
    Kernel::System::Main
    Kernel::System::SysConfig
    Kernel::System::GenericInterface::Webservice
    Kernel::System::YAML
    Kernel::System::Valid
);

=head1 NAME

var::packagesetup::Webservice-CustomerOperations - code to excecute during package installation

=head1 SYNOPSIS

All functions

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item CodeInstall()

run the code install part

    my $Result = $CodeObject->CodeInstall();

=cut

sub CodeInstall {
    my ( $Self, %Param ) = @_;

    # create dynamic fields
    $Self->_InstallWebservice();

    return 1;
}

=item CodeReinstall()

run the code reinstall part

    my $Result = $CodeObject->CodeReinstall();

=cut

sub CodeReinstall {
    my ( $Self, %Param ) = @_;

    return 1;
}

=item CodeUpgrade()

run the code upgrade part

    my $Result = $CodeObject->CodeUpgrade();

=cut

sub CodeUpgrade {
    my ( $Self, %Param ) = @_;

    $Self->_InstallWebservice();

    return 1;
}

=item CodeUninstall()

run the code uninstall part

    my $Result = $CodeObject->CodeUninstall();

=cut

sub CodeUninstall {
    my ( $Self, %Param ) = @_;

    return 1;
}

=item _InstallWebservice()

=cut

sub _InstallWebservice {
    my ( $Self, %Param ) = @_;

    my $YAMLObject = $Kernel::OM->Get('Kernel::System::YAML');
    my $Location   = join '/',
        $Kernel::OM->Get('Kernel::Config')->Get('Home'),
        qw/var GenericInterface CRM.yml/;

    my $Content = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
        Location => $Location,
    );

    my $ImportedConfig = $YAMLObject->Load( Data => ${$Content} );

    # display any YAML error message as a normal otrs error message
    if ( !IsHashRefWithData($ImportedConfig) ) {
        return;
    }

    # check if imported configuration has current framework version otherwise update it
    #if ( $ImportedConfig->{FrameworkVersion} ne $Self->{FrameworkVersion} ) {
    #    $ImportedConfig = $Self->_UpdateConfiguration( Configuration => $ImportedConfig );
    #}

    # remove framework information since is not needed anymore
    delete $ImportedConfig->{FrameworkVersion};

    # get webservice name
    my $WebserviceName   = basename $Location;
    my $WebserviceObject = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice');

    # remove file extension
    $WebserviceName =~ s{\.[^.]+$}{}g;

    # check if name is duplicated
    my %WebserviceList = reverse %{ $WebserviceObject->WebserviceList() };

    if ( $WebserviceList{$WebserviceName} ) {
        my $Success = $WebserviceObject->WebserviceUpdate(
            Name    => $WebserviceName,
            Config  => $ImportedConfig,
            ValidID => 1,
            UserID  => 1,
        );
    }

    # otherwise save configuration and return to overview screen
    my $Success = $WebserviceObject->WebserviceAdd(
        Name    => $WebserviceName,
        Config  => $ImportedConfig,
        ValidID => 1,
        UserID  => 1,
    );

    return 1;
}

1;

=back

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/gpl-2.0.txt>.

=cut
