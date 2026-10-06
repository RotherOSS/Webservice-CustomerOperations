# --
# Copyright (C) 2018 Perl-Services.de, http://perl-services.de
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::Customer::CustomerUserUpsert;

use v5.24;
use strict;
use warnings;

use parent qw(
    Kernel::GenericInterface::Operation::Common
    Kernel::GenericInterface::Operation::Customer::Common
);

# core modules

# CPAN modules

# OTOBO modules
use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsString IsStringWithData);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Operation::Customer::CustomerUserUpsert - GenericInterface Customer CustomerUserUpsert Operation backend

=head1 PUBLIC INTERFACE

=head2 new()

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

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::CustomerUserUpsert');

    return $Self;
}

=head2 Run()

perform CustomerUserUpsert Operation. This function is able to accept
one or more customer user entries in one call and returns successfully
inserted or updated customer user logins.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin => 'some agent login',                          # UserLogin or SessionID is required
            SessionID => 123,
            Password  => 'some password',                             # if UserLogin is sent then Password is required

            CustomerUser => {                                         # Single customer user or customer user list is required
                UserLogin      => 'tc',
                ID             => 'oldtc',                            # required for UserLogin-update (if no such customer user
                                                                      # exists, this will be ignored by the default mapping and
                                                                      # instead a new customer user via UserLogin is inserted)
                UserFirstname  => 'Test',
                UserLastname   => 'Customer',
                UserPassword   => 'some-pass',                        # not required
                UserEmail      => 'test.customer@example.com',
                UserCustomerID => '12345',                            # required when inserting
                ValidID        => 1,
            },
            CustomerUser => [
                {
                    UserLogin      => 'tc',
                    UserPassword   => 'some-pass',
                    UserFirstname  => 'Test',
                    UserLastname   => 'Customer',
                    UserEmail      => 'test.customer@example.com',
                    UserCustomerID => '12345',
                    ValidID        => 1,
                },
                {
                    # . . .
                },
            ],
        },
    );

    $Result = {
        Success         => 1,                                          # 0 or 1
        ErrorMessage    => '',                                         # in case of error
        Data            => {                                           # result data payload after Operation
            CustomerUser => [                                          # includes all customers users that
                                                                       # have been successfully upserted
                {
                    UserLogin   => 'tc',
                },
                {
                    # . . .
                },
            ],
            Error => {                                                 # should not return errors
                    ErrorCode    => 'CustomerUser.Upsert.ErrorCode'
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
        return $Self->ReturnError(
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
            ErrorCode    => 'CustomerUserUpsert.MissingParameter',
            ErrorMessage => "CustomerUserUpsert: UserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUserUpsert.MissingParameter',
                ErrorMessage => "CustomerUserUpsert: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerUserUpsert.AuthFail',
            ErrorMessage => "CustomerUserUpsert: User could not be authenticated!",
        );
    }

    my $PermissionUserID = $UserID;

    # check needed stuff
    for my $Needed (qw(CustomerUser)) {
        if ( !$Param{Data}->{$Needed} ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUserUpsert.MissingParameter',
                ErrorMessage => "CustomerUserUpsert: $Needed parameter is missing or not valid!",
            );
        }
    }

    # transform single customer users to an array reference
    if ( !IsArrayRefWithData( $Param{Data}{CustomerUser} ) ) {
        $Param{Data}{CustomerUser} = [ $Param{Data}{CustomerUser} ];
    }

    $Result = {
        Success => 1,
        Data    => {
            CustomerUser => [],
        }
    };

    # upsert each customer user
    for my $CustomerUser ( @{ $Param{Data}{CustomerUser} } ) {

        # remove leading and trailing spaces
        ATTRIBUTE:
        for my $Attribute ( sort keys %{$CustomerUser} ) {
            next ATTRIBUTE if !$CustomerUser->{$Attribute};
            next ATTRIBUTE if ref $CustomerUser->{$Attribute} eq 'HASH';
            next ATTRIBUTE if ref $CustomerUser->{$Attribute} eq 'ARRAY';

            $CustomerUser->{$Attribute} =~ s{\A\s+}{};
            $CustomerUser->{$Attribute} =~ s{\s+\z}{};
        }

        my $CustomerUserCheck = $Self->_CheckCustomerUser( CustomerUser => $CustomerUser );

        # if an error occurs, return, but still include all customer users already upserted
        if ( !$CustomerUserCheck->{Success} ) {
            $Result->{Success}       = 0;
            $Result->{ErrorMessage}  = "$CustomerUserCheck->{ErrorCode}: $CustomerUserCheck->{ErrorMessage}";
            $Result->{Data}->{Error} = {
                ErrorCode    => $CustomerUserCheck->{ErrorCode},
                ErrorMessage => $CustomerUserCheck->{ErrorMessage},
            };

            return $Result;
        }

        my $UpsertResult = $Self->_CustomerUserUpsert(
            CustomerUser => $CustomerUser,
            UserID       => $UserID,
        );

        # if an error occurs, return, but still include all customer users already upserted
        if ( !$UpsertResult->{Success} ) {
            $Result->{Success}      = 0;
            $Result->{ErrorMessage} = $UpsertResult->{ErrorMessage};

            return $Result;
        }

        push @{ $Result->{Data}->{CustomerUser} }, $UpsertResult->{Data};
    }

    return $Result;
}

=begin Internal:

=head2 _CheckCustomerUser()

checks if the given customer user parameters are valid.

    my $CustomerUserCheck = $OperationObject->_CheckCustomerUser(
        CustomerUser => $CustomerUser,                               # all customer user parameters
    );

    returns:

    $CustomerUserCheck = {
        Success => 1,                                                # if everything is OK
    }

    $CustomerUserCheck = {
        ErrorCode    => 'Function.Error',                            # if error
        ErrorMessage => 'Error description',
    }

=cut

sub _CheckCustomerUser {
    my ( $Self, %Param ) = @_;

    my $CustomerUser = $Param{CustomerUser};

    # check customer user internally
    for my $Needed (qw(UserFirstname UserLastname UserLogin UserEmail)) {
        if ( !$CustomerUser->{$Needed} ) {
            return {
                ErrorCode    => 'CustomerUserUpsert.MissingParameter',
                ErrorMessage => "CustomerUseUpsertt: CustomerUser->$Needed parameter is missing!",
            };
        }
    }

    # if everything is OK then return Success
    return {
        Success => 1,
    };
}

=head2 _CustomerUserUpsert()

updates or inserts a customer user.

    my $Response = $OperationObject->_CustomerUserUpsert(
        CustomerUser => $CustomerUser,                                # all customer user parameters
        UserID       => 123,
    );

    returns:

    $Response = {
        Success => 1,                                                 # if everething is OK
        Data    => {
            CustomerUserID => 123,
        }
    }

    $Response = {
        Success      => 0,                                            # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerUserUpsert {
    my ( $Self, %Param ) = @_;

    my $CustomerUser      = $Param{CustomerUser};
    my $CustomerUserLogin = $CustomerUser->{UserLogin};

    # customer users are by default valid
    $CustomerUser->{ValidID} //= 1;

    # get customer user object
    my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

    # check whether this customer user exists (update) or is new (insert)
    $CustomerUser->{ID} ||= $CustomerUser->{UserLogin};

    my %User = $CustomerUserObject->CustomerUserDataGet(
        User   => $CustomerUser->{ID},
        UserID => $Param{UserID},
    );
    if (%User) {
        my $Success = $CustomerUserObject->CustomerUserUpdate(
            %{$CustomerUser},
            UserID => $Param{UserID},
        );

        if ( !$Success ) {
            return {
                Success      => 0,
                ErrorMessage => 'Customer could not be updated, please contact the system administrator',
            };
        }
    }
    else {
        # when adding a new customer user, the customer (company) is required
        if ( !$CustomerUser->{UserCustomerID} ) {
            return {
                ErrorCode    => 'CustomerUserUpsert.MissingParameter',
                ErrorMessage => "CustomerUseUpsertt: CustomerUser->UserCustomerID parameter is missing!",
            };
        }

        $CustomerUserLogin = $CustomerUserObject->CustomerUserAdd(
            %{$CustomerUser},
            UserID => $Param{UserID},
        );

        if ( !$CustomerUserLogin ) {
            return {
                Success      => 0,
                ErrorMessage => 'Customer could not be inserted, please contact the system administrator',
            };
        }
    }

    my %CustomerUserData = $CustomerUserObject->CustomerUserDataGet(
        User   => $CustomerUserLogin,
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
            UserLogin => $CustomerUserLogin,
        },
    };
}

1;

=end Internal:

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
