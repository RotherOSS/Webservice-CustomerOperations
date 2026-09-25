# --
# Copyright (C) 2018 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::CustomerUser::CustomerUserCreate;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

use base qw(
    Kernel::GenericInterface::Operation::Common
    Kernel::GenericInterface::Operation::CustomerUser::Common
);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Operation::CustomerUser::CustomerUserCreate

=head1 SYNOPSIS

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

usually, you want to create an instance of this
by using Kernel::GenericInterface::Operation->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw( DebuggerObject WebserviceID )) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::CustomerUserCreate');

    return $Self;
}

=item Run()

perform CustomerUserCreate Operation. This will return the created customer number.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin => 'some agent login',       # UserLogin or SessionID is required
            SessionID => 123,
            Password  => 'some password',          # if UserLogin is sent then Password is required

            CustomerUser => {
                UserLogin      => 'tc',
                UserFirstname  => 'Test',
                UserLastname   => 'Customer',
                UserCustomerID => '12345',
                ValidID        => 1,
            },
        },
    );

    $Result = {
        Success         => 1,                       # 0 or 1
        ErrorMessage    => '',                      # in case of error
        Data            => {                        # result data payload after Operation
            UserLogin   => 'tc',
            Error => {                              # should not return errors
                    ErrorCode    => 'CustomerUser.Create.ErrorCode'
                    ErrorMessage => 'Error Description'
            },
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my $Result = $Self->Init(
        WebserviceID => $Self->{WebserviceID},
    );

    if ( !$Result->{Success} ) {
        $Self->ReturnError(
            ErrorCode    => 'Webservice.InvalidConfiguration',
            ErrorMessage => $Result->{ErrorMessage},
        );
    }

    # check needed stuff
    if (
        !$Param{Data}->{UserLogin}
        && !$Param{Data}->{SessionID}
        )
    {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerUserCreate.MissingParameter',
            ErrorMessage => "CustomerUserCreate: UserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUserCreate.MissingParameter',
                ErrorMessage => "CustomerUserCreate: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerUserCreate.AuthFail',
            ErrorMessage => "CustomerUserCreate: User could not be authenticated!",
        );
    }

    my $PermissionUserID = $UserID;

    # check needed hashes
    for my $Needed (qw(CustomerUser)) {
        if ( !IsHashRefWithData( $Param{Data}->{$Needed} ) ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUserCreate.MissingParameter',
                ErrorMessage => "CustomerUserCreate: $Needed parameter is missing or not valid!",
            );
        }
    }

    # isolate customer parameter
    my $CustomerUser = $Param{Data}->{CustomerUser};

    # remove leading and trailing spaces
    for my $Attribute ( sort keys %{$CustomerUser} ) {
        if ( ref $Attribute ne 'HASH' && ref $Attribute ne 'ARRAY' ) {

            #remove leading spaces
            $CustomerUser->{$Attribute} =~ s{\A\s+}{};

            #remove trailing spaces
            $CustomerUser->{$Attribute} =~ s{\s+\z}{};
        }
    }

    my $CustomerUserCheck = $Self->_CheckCustomerUser( CustomerUser => $CustomerUser );

    if ( !$CustomerUserCheck->{Success} ) {
        return $Self->ReturnError( %{$CustomerUserCheck} );
    }

    return $Self->_CustomerUserCreate(
        CustomerUser => $CustomerUser,
        UserID   => $UserID,
    );
}

=begin Internal:

=item _CheckCustomerUser()

checks if the given customer parameters are valid.

    my $CustomerUserCheck = $OperationObject->_CheckCustomerUser(
        CustomerUser => $CustomerUser,                          # all customer parameters
    );

    returns:

    $CustomerUserCheck = {
        Success => 1,                               # if everything is OK
    }

    $CustomerUserCheck = {
        ErrorCode    => 'Function.Error',           # if error
        ErrorMessage => 'Error description',
    }

=cut

sub _CheckCustomerUser {
    my ( $Self, %Param ) = @_;

    my $CustomerUser = $Param{CustomerUser};

    # check customer internally
    for my $Needed (qw(UserFirstname UserLastname UserLogin UserEmail UserCompanyID)) {
        if ( !$CustomerUser->{$Needed} ) {
            return {
                ErrorCode    => 'CustomerUserCreate.MissingParameter',
                ErrorMessage => "CustomerUserCreate: CustomerUser->$Needed parameter is missing!",
            };
        }
    }

    # if everything is OK then return Success
    return {
        Success => 1,
    };
}

=item _CustomerUserCreate()

creates a customer with its article and sets dynamic fields and attachments if specified.

    my $Response = $OperationObject->_CustomerUserCreate(
        CustomerUser => $CustomerUser,       # all customer parameters
        UserID   => 123,
    );

    returns:

    $Response = {
        Success => 1,                # if everething is OK
        Data => {
            CustomerUserID => 123,
        }
    }

    $Response = {
        Success      => 0,           # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerUserCreate {
    my ( $Self, %Param ) = @_;

    my $CustomerUser = $Param{CustomerUser} // {};

    # get customer object
    my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

    # create new customer
    my $CustomerUserID = $CustomerUserObject->CustomerUserAdd(
        %{ $CustomerUser },
        ValidID      => $CustomerUser->{ValidID} // 1,
        UserID       => $Param{UserID},
    );

    if ( !$CustomerUserID ) {
        return {
            Success      => 0,
            ErrorMessage => 'CustomerUser could not be created, please contact the system administrator',
        };
    }

    my %CustomerUserData = $CustomerUserObject->CustomerUserDataGet(
        User   => $CustomerUser->{UserLogin},
        UserID => $Param{UserID},
    );

    if ( !IsHashRefWithData( \%CustomerUserData ) ) {
        return {
            Success      => 0,
            ErrorMessage => 'Could not get new customer user information, please contact the system'
                . ' administrator',
        };
    }

    return {
        Success => 1,
        Data    => {
            UserLogin => $CustomerUserData{UserLogin},
        },
    };
}

1;

=end Internal:

=back

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
