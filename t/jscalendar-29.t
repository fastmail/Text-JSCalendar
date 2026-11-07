#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;
use JSON::PP ();
use Text::JSCalendar;

# Changes in jscalendarbis-22 and jscalendar-icalendar-29 (other than links,
# which t/links.t covers).

my $jscal = Text::JSCalendar->new();
my $true = JSON::PP::true();
sub unfold { my $i = shift; $i =~ s/\r?\n[ \t]//g; return $i }
sub ics { join("\r\n", 'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:x', @_, 'END:VCALENDAR', '') }
sub vevent { ics('BEGIN:VEVENT', 'UID:t@example.com', 'DTSTAMP:20250101T000000Z', @_, 'END:VEVENT') }
sub event { my ($e) = $jscal->vcalendarToEvents(vevent(@_)); return $e }

# timeZone may not be null (jscalendarbis-22 3.6.1; -29 2.1.5)
{
  my $e = event('DTSTART:20240921T105302', 'DURATION:PT1H');
  ok(!exists $e->{timeZone}, 'floating time: timeZone not set (was null)');
  is($e->{start}, '2024-09-21T10:53:02', 'start');
  ok(!exists event('DTSTART;VALUE=DATE:20240921')->{timeZone}, 'DATE: timeZone not set');
  is(event('DTSTART;TZID=America/Chicago:20250521T080000')->{timeZone}, 'America/Chicago', 'a zone is kept');
}

# CLASS: any other value MUST be private (-29 2.3.7)
{
  is(event('DTSTART:20250101T100000Z', 'CLASS:X-SECRET-ISH')->{privacy}, 'private', 'unknown CLASS is private');
  is(event('DTSTART:20250101T100000Z', 'CLASS:CONFIDENTIAL')->{privacy}, 'secret', 'CONFIDENTIAL is secret');
  is(event('DTSTART:20250101T100000Z', 'CLASS:PRIVATE')->{privacy}, 'private', 'PRIVATE is private');
  ok(!exists event('DTSTART:20250101T100000Z', 'CLASS:PUBLIC')->{privacy}, 'PUBLIC is the default');
}

# showWithoutTime (-29 2.3.38, 3.2): DATE only with no time zone and no time
# of day; otherwise the time and zone stay and SHOW-WITHOUT-TIME is written
{
  my $base = { '@type' => 'Event', uid => 'swt@example.com', title => 'x' };
  my $ical = unfold($jscal->eventsToVCalendar({ %$base, start => '2025-05-21T08:00:00',
    timeZone => 'America/Chicago', duration => 'PT12H', showWithoutTime => $true }));
  like($ical, qr/^DTSTART;TZID=America\/Chicago:20250521T080000\r?$/m, 'a timed event shown without time keeps its time and zone');
  like($ical, qr/^SHOW-WITHOUT-TIME;VALUE=BOOLEAN:TRUE\r?$/m, 'and says SHOW-WITHOUT-TIME');
  my ($back) = $jscal->vcalendarToEvents($ical);
  is($back->{start}, '2025-05-21T08:00:00', 'the -29 example round-trips: start');
  is($back->{timeZone}, 'America/Chicago', 'timeZone');
  ok($back->{showWithoutTime}, 'showWithoutTime');

  $ical = unfold($jscal->eventsToVCalendar({ %$base, start => '2025-05-21T00:00:00',
    timeZone => 'America/Chicago', duration => 'P1D', showWithoutTime => $true }));
  like($ical, qr/^DTSTART;TZID=America\/Chicago:20250521T000000\r?$/m, 'midnight with a time zone is not DATE');

  $ical = unfold($jscal->eventsToVCalendar({ %$base, start => '2025-05-21T00:00:00',
    duration => 'P2D', showWithoutTime => $true }));
  like($ical, qr/^DTSTART;VALUE=DATE:20250521\r?$/m, 'midnight, no zone, whole days: DATE');
  unlike($ical, qr/^SHOW-WITHOUT-TIME/m, 'and no SHOW-WITHOUT-TIME');
}

# a Task alert MUST NOT be relative to "end" without a due (jscalendarbis-22 3.5.1)
{
  my $todo = sub { my ($t) = $jscal->vcalendarToEvents(ics('BEGIN:VTODO', 'UID:todo@example.com',
    'DTSTAMP:20250101T000000Z', 'DTSTART:20250101T100000Z', @_, 'END:VTODO')); return $t };
  my $alert = sub { my ($t) = @_; my ($a) = values %{ $t->{alerts} || {} }; return $a->{trigger} };
  my $alarm = sub { ('BEGIN:VALARM', 'ACTION:DISPLAY', 'DESCRIPTION:x', "TRIGGER;RELATED=END:$_[0]", 'END:VALARM') };
  is_deeply($alert->($todo->('DURATION:PT2H', $alarm->('-PT15M'))),
    { '@type' => 'OffsetTrigger', offset => 'PT1H45M', relativeTo => 'start' },
    'no DUE: 15 minutes before DTSTART + DURATION, relative to start');
  is_deeply($alert->($todo->($alarm->('-PT15M'))),
    { '@type' => 'OffsetTrigger', offset => '-PT15M', relativeTo => 'start' },
    'no DUE and no DURATION: the end is the start');
  is($alert->($todo->('DUE:20250101T120000Z', $alarm->('-PT15M')))->{relativeTo}, 'end', 'with DUE, end stays');
}

# SENT-BY: the participant's sentBy, and the ORGANIZER's is also the
# Event's (jscalendar-icalendar-29 2.3.29)
{
  my $e = event('DTSTART:20250101T100000Z',
    'ORGANIZER;SENT-BY="mailto:assistant@example.com";CN=Boss:mailto:boss@example.com',
    'ATTENDEE;SENT-BY="mailto:proxy@example.com";PARTSTAT=ACCEPTED:mailto:alice@example.com');
  is($e->{sentBy}, 'assistant@example.com', 'ORGANIZER SENT-BY is the Event sentBy');
  my ($org) = grep { $_->{calendarAddress} eq 'mailto:boss@example.com' } values %{$e->{participants}};
  my ($att) = grep { $_->{calendarAddress} eq 'mailto:alice@example.com' } values %{$e->{participants}};
  is($org->{sentBy}, 'assistant@example.com', 'and the organizer participant\'s');
  is($att->{sentBy}, 'proxy@example.com', 'ATTENDEE SENT-BY is the participant sentBy');
  my $ical = unfold($jscal->eventsToVCalendar($e));
  like($ical, qr/^ORGANIZER;[^\n]*SENT-BY="?mailto:assistant\@example\.com"?/m, 'written back on ORGANIZER');
  like($ical, qr/^ATTENDEE;[^\n]*SENT-BY="?mailto:proxy\@example\.com"?[^\n]*:mailto:alice/m, 'and on ATTENDEE');
  ok(!exists event('DTSTART:20250101T100000Z')->{sentBy}, 'no organizer, no sentBy');
}

done_testing;
