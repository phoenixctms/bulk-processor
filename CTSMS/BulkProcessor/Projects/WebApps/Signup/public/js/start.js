


function initPrimeUI(context) {

    context.sitesVisible = 3;

    $('#images').puigalleria({
        showCaption: false,
        showFilmstrip: false,
        panelWidth: '100%',
        panelHeight: '20%',
        //panelHeight: 180,
        transitionInterval: 10000
    });


    $("#sites").puicarousel({
        headerText: context.trialSitesHeader,

        datasource: context.siteOptions,
        autoplayInterval: 0,
        effectDuration: 1000,
        easing: 'easeInOutSine',

        navigate: function(event, ui) {
            $("#sites").puicarousel('stopAutoplay');
        },
        numVisible: context.sitesVisible,
        itemContent: function(site) {
            context.siteStatusVar = {
                site: site
            };

            var content = $('<div class="ctsms-site-item"/>');

            var grid = $('<div class="ui-grid"/>');
            var row = $('<div class="ui-grid-row"/>');

            row.append($('<div class="ui-grid-col-5"/>').append($('<div class="ctsms-site-label"/>').append($('<span />').append(document.createTextNode(site.label)))));

                var button = $('<button name="site" type="submit" value="' + site.site + '">' + context.selectSiteBtnLabel + '</button>').puibutton({
                    icon: 'fa-caret-right',
                    iconPos: 'right'
                });
                if (!site.register || context.probandCreated && site.departmentId != context.probandDepartmentId) {
                    button.puibutton('disable');
                }
                row.append($('<div class="ui-grid-col-7" style="text-align:right;"/>').append(button));

            grid.append(row);

            row = $('<div class="ui-grid-row"/>');
            var iframeId = site.site + '_site_description';
            row.append($('<div class="ui-grid-col-12 ui-widget ui-widget-content ui-corner-all ' + (site.selected ? 'ui-shadow ' : '') + 'ctsms-site-description"/>').append(createIframe(iframeId, site.description)));
            grid.append(row);

            var mapId = site.site + '_map';
            row = $('<div class="ui-grid-row"/>');
            row.append($('<div class="ui-grid-col-12"/>').append('<div class="' + (site.showMap ? 'map' : 'map-hidden') + '" id="' + mapId + '"/>'));
            grid.append(row);

            content.append(grid);

            return content;

        },
        initContent: function(content) {
            var site = context.siteStatusVar.site;
            var iframeId = site.site + '_site_description';
            initIframe(iframeId, site.description);
            initSiteLocationMap(site);
        }

    });

    $('#messages').puimessages();
    if (context.apiError != null) {
        setMessages('warn', context.apiError );
    }

    $('#form').submit(function() {
        return _sanitizeForm(context);
    });

}






function _sanitizeForm(context) {



    showWaitDlg();


    return true;
}

function initSiteLocationMap(site) {
    if (site.showMap) {
        var mapId = site.site + '_map';
        var location = { lat: parseFloat(site.latitude), lng: parseFloat(site.longitude) };
        var map = new google.maps.Map(document.getElementById(mapId), {
            zoom: 16,
            mapTypeControl: false,
            center: location,
            streetViewControl: false,
            mapTypeId: google.maps.MapTypeId.ROADMAP
        });
        var marker = new google.maps.Marker({
            position: location,
            map: map
        });
    }
}
