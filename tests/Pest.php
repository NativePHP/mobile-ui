<?php

use Illuminate\Container\Container;
use Illuminate\Support\Facades\Facade;

/**
 * Core resolves platform icons, ios:/android: classes and the like through
 * the System facade (nativephp/mobile 4.7+), but most of this suite renders
 * elements without booting an app. A bare container is all System needs to
 * resolve. Files that boot Testbench swap in their own app.
 */
Facade::setFacadeApplication(new Container);

uses()->in('.');
