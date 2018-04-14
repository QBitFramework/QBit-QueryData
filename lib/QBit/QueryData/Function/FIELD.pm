package QBit::QueryData::Function::FIELD;

use qbit;

use base qw(QBit::QueryData::Function);

sub init {
    my ($self) = @_;

    $self->SUPER::init();

    return FALSE if $self->has_errors();

    if ($self->args->[0] eq '') {
        $self->{'PATH'}           = $self->path;
        $self->{'__MAIN_FIELD__'} = $self->field;
    } else {
        $self->{'PATH'}           = $self->qd->_get_path($self->args->[0]);
        $self->{'__MAIN_FIELD__'} = $self->args->[0];
    }
}

sub process {
    my ($self) = @_;

    return
        '        $new_row->{'
      . $self->qd->quote($self->field) . '} = '
      . $self->qd->_get_field_code_by_path('$row', $self->{'PATH'}) . ';
';
}

sub check {TRUE}

sub set_args {
    my ($self) = @_;

    $self->{'args'} = [$self->fields->{$self->field}];
}

sub check_args {
    my ($self) = @_;

    my $key;
    if ($self->args->[0] eq '') {
        $key = $self->path->[0]{'key'};
    } else {
        $key = $self->qd->_get_path($self->args->[0])->[0]{'key'};
    }

    unless (exists($self->qd->{'__ALL_FIELDS__'}{$key})) {
        $self->set_error(gettext('Fields "%s" not exists', $key));

        return FALSE;
    }

    return TRUE;
}

TRUE;
