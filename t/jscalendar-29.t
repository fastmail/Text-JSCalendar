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

done_testing;
