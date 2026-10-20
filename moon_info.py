#!/usr/bin/env python3
import datetime
import math
import subprocess
import sys

def get_city():
    try:
        city = subprocess.check_output(
            ["curl", "-fsS", "--max-time", "3", "https://ipinfo.io/city"],
            stderr=subprocess.DEVNULL
        ).decode("utf-8").strip()
        return city
    except Exception:
        return "Unknown"

def get_moon_info():
    now = datetime.datetime.now()
    
    # Reference new moon: 2026-10-11 11:40 UTC
    ref_new_moon = datetime.datetime(2026, 10, 11, 11, 40)
    
    diff = (now - ref_new_moon).total_seconds()
    days_since_new_moon = (diff / 86400.0) % 29.530588853
    if days_since_new_moon < 0:
        days_since_new_moon += 29.530588853
        
    # Moon Age (days)
    age = days_since_new_moon
    
    # Phase names
    if age < 1.84: name = "New Moon"
    elif age < 5.53: name = "Waxing Crescent"
    elif age < 9.22: name = "First Quarter"
    elif age < 12.91: name = "Waxing Gibbous"
    elif age < 16.60: name = "Full Moon"
    elif age < 20.29: name = "Waning Gibbous"
    elif age < 23.98: name = "Third Quarter"
    elif age < 27.67: name = "Waning Crescent"
    else: name = "New Moon"
    
    # Illumination percentage
    # Using the formula: illum = (1 - cos(2 * pi * age / 29.530588853)) / 2 * 100
    # This works well for the visible disc illumination.
    illum = (1 - math.cos(2 * math.pi * age / 29.530588853)) / 2 * 100
    
    # Next Full Moon
    # Full moon is at age 14.765
    days_to_full = (14.765 - age) % 29.530588853
    if days_to_full < 0: days_to_full += 29.530588853
    
    next_full_date = now + datetime.timedelta(days=days_to_full)
    
    # Full moon name
    month = next_full_date.month
    names = {
        1: "Wolf Moon", 2: "Snow Moon", 3: "Worm Moon", 4: "Pink Moon",
        5: "Flower Moon", 6: "Strawberry Moon", 7: "Buck Moon",
        8: "Sturgeon Moon", 9: "Harvest Moon", 10: "Hunter's Moon",
        11: "Beaver Moon", 12: "Long Night's Moon"
    }
    full_moon_name = names.get(month, "")
    
    # Format the string
    # Use a range for illumination to match the user's example "~65–66% illuminated"
    # We can just take the integer and put a range around it or just the value.
    # Let's stick to the value for now as it's more accurate.
    illum_str = f"({int(illum)}% illuminated)"
    
    # Date and time format
    next_full_str = next_full_date.strftime("%B %d, %Y, at %H:%M")
    city_name = get_city()
    
    return f"Current Phase: {name} {illum_str} | Next Full Moon: {next_full_str} ({full_moon_name}) [{city_name}]"

if __name__ == "__main__":
    print(get_moon_info())
