# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminPostMasterFilter;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ParamObject    = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $ConfigObject   = $Kernel::OM->Get('Kernel::Config');
    my $Name           = $ParamObject->GetParam( Param => 'Name' );
    my $OldName        = $ParamObject->GetParam( Param => 'OldName' );
    my $StopAfterMatch = $ParamObject->GetParam( Param => 'StopAfterMatch' ) || 0;
    my %GetParam       = ();

    for my $Number ( 1 .. $ConfigObject->Get('PostmasterHeaderFieldCount') ) {
        $GetParam{"MatchHeader$Number"} = $ParamObject->GetParam( Param => "MatchHeader$Number" );
        $GetParam{"MatchValue$Number"}  = $ParamObject->GetParam( Param => "MatchValue$Number" );
        $GetParam{"MatchNot$Number"}    = $ParamObject->GetParam( Param => "MatchNot$Number" );
        $GetParam{"SetHeader$Number"}   = $ParamObject->GetParam( Param => "SetHeader$Number" );
        $GetParam{"SetValue$Number"}    = $ParamObject->GetParam( Param => "SetValue$Number" );
    }

    my $LayoutObject     = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $PostMasterFilter = $Kernel::OM->Get('Kernel::System::PostMaster::Filter');

    # ------------------------------------------------------------ #
    # delete
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Delete' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $Delete = $PostMasterFilter->FilterDelete(
            Name => $Name,
        );

        if ( !$Delete ) {
            return $LayoutObject->ErrorScreen();
        }

        return $LayoutObject->Attachment(
            ContentType => 'text/html',
            Content     => $Delete,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # ------------------------------------------------------------ #
    # add action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'AddAction' ) {
        return $Self->_MaskUpdate( Data => {} );
    }

    # ------------------------------------------------------------ #
    # update
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Update' ) {
        my %Data = $PostMasterFilter->FilterGet( Name => $Name );
        if ( !%Data ) {
            return $LayoutObject->ErrorScreen(
                Message => $LayoutObject->{LanguageObject}->Translate( 'No such filter: %s', $Name ),
            );
        }
        return $Self->_MaskUpdate(
            Name => $Name,
            Data => \%Data,
        );
    }

    # ------------------------------------------------------------ #
    # update action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'UpdateAction' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my %Match = ();
        my %Set   = ();
        my %Not;

        for my $Number ( 1 .. $ConfigObject->Get('PostmasterHeaderFieldCount') ) {
            if ( $GetParam{"MatchHeader$Number"} && length $GetParam{"MatchValue$Number"} ) {
                $Match{ $GetParam{"MatchHeader$Number"} } = $GetParam{"MatchValue$Number"};
                $Not{ $GetParam{"MatchHeader$Number"} }   = $GetParam{"MatchNot$Number"};
            }

            if ( $GetParam{"SetHeader$Number"} && length $GetParam{"SetValue$Number"} ) {
                $Set{ $GetParam{"SetHeader$Number"} } = $GetParam{"SetValue$Number"};
            }
        }
        my %Errors = ();
        if (%Match) {
            my $InvalidCount = 0;
            for my $MatchKey ( sort keys %Match ) {
                $InvalidCount++;
                my $MatchValue = $Match{$MatchKey};
                if ( !eval { my $Regex = qr/$MatchValue/; 1; } ) {
                    $Errors{"MatchHeader${InvalidCount}Invalid"} = 'ServerError';
                    $Errors{"MatchValue${InvalidCount}Invalid"}  = 'ServerError';
                }
            }
        }
        else {
            $Errors{"MatchHeader1Invalid"} = 'ServerError';
            $Errors{"MatchValue1Invalid"}  = 'ServerError';
        }

        if (%Set) {
            my $InvalidCount = 0;
            for my $SetKey ( sort keys %Set ) {
                $InvalidCount++;
                if ( !length $Set{$SetKey} ) {
                    $Errors{"SetHeader${InvalidCount}Invalid"} = 'ServerError';
                    $Errors{"SetValue${InvalidCount}Invalid"}  = 'ServerError';
                }
            }
        }
        else {
            $Errors{"SetHeader1Invalid"} = 'ServerError';
            $Errors{"SetValue1Invalid"}  = 'ServerError';
        }

        # Name validation
        if ( $Name eq '' ) {
            $Errors{"NameInvalid"} = 'ServerError';
        }

        if (%Errors) {
            return $Self->_MaskUpdate(
                Name => $Name,
                Data => {
                    %Errors,
                    Name           => $Name,
                    Set            => \%Set,
                    Match          => \%Match,
                    StopAfterMatch => $StopAfterMatch,
                    Not            => \%Not,
                },
            );
        }
        $PostMasterFilter->FilterDelete( Name => $OldName );
        $PostMasterFilter->FilterAdd(
            Name           => $Name,
            Match          => \%Match,
            Set            => \%Set,
            StopAfterMatch => $StopAfterMatch,
            Not            => \%Not,
        );

        # if the user would like to continue editing the postmaster filter, just redirect to the update screen
        if ( defined $ParamObject->GetParam( Param => 'ContinueAfterSave' )
            && ( $ParamObject->GetParam( Param => 'ContinueAfterSave' ) eq '1' ) ) {
            return $LayoutObject->Redirect( OP => "Action=$Self->{Action};Subaction=Update;Name=$Name" );
        }
        else {

            # otherwise return to overview
            return $LayoutObject->Redirect( OP => "Action=$Self->{Action}" );
        }

        return $LayoutObject->Redirect( OP => "Action=$Self->{Action}" );
    }

    # ------------------------------------------------------------ #
    # overview
    # ------------------------------------------------------------ #
    else {
        my %List = $PostMasterFilter->FilterList();

        $LayoutObject->Block(
            Name => 'Overview',
            Data => { %Param, },
        );
        $LayoutObject->Block( Name => 'ActionList' );
        $LayoutObject->Block( Name => 'ActionAdd' );
        $LayoutObject->Block( Name => 'Filter' );

        $LayoutObject->Block(
            Name => 'OverviewResult',
            Data => { %Param, },
        );
        if (%List) {
            for my $Key ( sort keys %List ) {
                $LayoutObject->Block(
                    Name => 'OverviewResultRow',
                    Data => {
                        Name => $Key,
                    },
                );
            }
        }
        else {
            $LayoutObject->Block(
                Name => 'NoDataFoundMsg',
                Data => {},
            );
        }

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminPostMasterFilter',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }
}

sub _MaskUpdate {
    my ( $Self, %Param ) = @_;

    my %Data    = %{ $Param{Data} };
    my $Counter = 0;
    if ( $Data{Match} ) {
        for my $MatchKey ( sort keys %{ $Data{Match} } ) {
            if ( $MatchKey && length $Data{Match}->{$MatchKey} ) {
                $Counter++;
                $Data{"MatchValue$Counter"}  = $Data{Match}->{$MatchKey};
                $Data{"MatchHeader$Counter"} = $MatchKey;
                $Data{"MatchNot$Counter"}    = $Data{Not}->{$MatchKey} ? ' checked="checked"' : '';
            }
        }
    }
    $Counter = 0;
    if ( $Data{Set} ) {
        for my $SetKey ( sort keys %{ $Data{Set} } ) {
            if ( $SetKey && length $Data{Set}->{$SetKey} ) {
                $Counter++;
                $Data{"SetValue$Counter"}  = $Data{Set}->{$SetKey};
                $Data{"SetHeader$Counter"} = $SetKey;
            }
        }
    }

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $Output = $LayoutObject->Header();
    $Output .= $LayoutObject->NavigationBar();

    $LayoutObject->Block(
        Name => 'Overview',
        Data => {
            Action => $Self->{Subaction},
            Name   => $Param{Name},
        },
    );
    $LayoutObject->Block( Name => 'ActionList' );
    $LayoutObject->Block( Name => 'ActionOverview' );

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # all headers
    my @Headers = @{ $ConfigObject->Get('PostmasterX-Header') };

    # add Dynamic Field headers
    my $DynamicFields = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldList(
        Valid      => 1,
        ObjectType => [ 'Ticket', 'Article' ],
        ResultType => 'HASH',
    );
    for my $DynamicField ( values %$DynamicFields ) {
        push @Headers, 'X-OTRS-DynamicField-' . $DynamicField;
        push @Headers, 'X-OTRS-FollowUp-DynamicField-' . $DynamicField;
    }

    my %Header = map { $_ => $_ } @Headers;
    $Header{''} = '-';
    $Header{Body} = 'Body';

    # otrs header
    my %SetHeader = ();
    for my $HeaderKey ( sort keys %Header ) {
        if ( $HeaderKey =~ /^x-otrs/i ) {
            $SetHeader{$HeaderKey} = $HeaderKey;
        }
    }
    $SetHeader{''} = '-';

    # build strings
    for my $Number ( 1 .. $ConfigObject->Get('PostmasterHeaderFieldCount') ) {
        $Data{"MatchHeader$Number"} = $LayoutObject->BuildSelection(
            Data        => \%Header,
            Name        => "MatchHeader$Number",
            SelectedID  => $Data{"MatchHeader$Number"},
            Class       => 'Modernize ' . ( $Data{ 'MatchHeader' . $Number . 'Invalid' } || '' ),
            Translation => 0,
            HTMLQuote   => 1,
        );
        $Data{"SetHeader$Number"} = $LayoutObject->BuildSelection(
            Data        => \%SetHeader,
            Name        => "SetHeader$Number",
            SelectedID  => $Data{"SetHeader$Number"},
            Class       => 'Modernize ' . ( $Data{ 'SetHeader' . $Number . 'Invalid' } || '' ),
            Translation => 0,
            HTMLQuote   => 1,
        );
    }
    $Data{"StopAfterMatch"} = $LayoutObject->BuildSelection(
        Data => {
            0 => 'No',
            1 => 'Yes'
        },
        Name        => 'StopAfterMatch',
        SelectedID  => $Data{StopAfterMatch} || 0,
        Class       => 'Modernize Validate_RequiredDropdown',
        Translation => 1,
        HTMLQuote   => 1,
    );

    $LayoutObject->Block(
        Name => 'OverviewUpdate',
        Data => {
            %Param, %Data,
            OldName => $Data{Name},
            Action  => $Self->{Subaction},
        },
    );

    $Output .= $LayoutObject->Output(
        TemplateFile => 'AdminPostMasterFilter',
        Data         => \%Param,
    );
    $Output .= $LayoutObject->Footer();
    return $Output;
}

1;
