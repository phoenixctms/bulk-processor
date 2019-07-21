
function initPrimeUI(context) {

    context.trialsPerPage = 4;
    context.trialsPerRow = 2; //3;

    $("#trials").puidatagrid({
        header: context.trialsGridHeader,
        paginator: {
            rows: context.trialsPerPage,
            page: +context.trialPage
        },
        lazy: true,
        columns: context.trialsPerRow,
        datasource: function(callback, ui, updateUi) {
            $.ajax({
                //type: "GET",
                url: context.uriBase + '/trials',
                data: { rows: ui.rows, first: ui.first },
                //dataType: "json",
                context: this,
                success: function(data) {
                    if(this.options.paginator) {
                        this.options.paginator.totalRecords = data.paginator.total_count;
                    };
                    callback.call(this, data.rows);
                    if (updateUi != null) {
                        updateUi(false);
                    }
                    hideWaitDlg();
                }
            });
        },
        content: function(trial) {
            var selected = (context.trial != null && context.trial.id == trial.id);
            if (context.trial != null && context.inquiryTrial != null && context.trial._activeInquiryCount == 0 && context.trial.signupInquiries) {
                selected = false;
            }
            var signedUp = (context.probandListEntryIdMap[trial.id] != null);
            context.trialStatusVar = {
                trial: trial
            };


            var grid = $('<div class="ui-grid"/>'); //ui-grid-responsive
            //var row = $('<div class="ui-grid-row"/>');
            //row.append($('<div class="ui-grid-col-8 ctsms-trial-name"/>').text(trial.name));
            //row.append($('<div class="ui-grid-col-4 ctsms-trial-department"/>').text(trial.department.name));
            //grid.append(row);

            var row = $('<div class="ui-grid-row"/>');
            var iframeId = trial.id + '_signup_description';
            row.append($('<div class="ui-grid-col-12 ui-widget ui-widget-content ui-corner-all ' + (selected ? 'ui-shadow ' : '') + 'ctsms-signup-description"/>').append(createIframe(iframeId, trial.signupDescription)));
            grid.append(row);

            row = $('<div class="ui-grid-row"/>');
            var _trial = (context.inquiryTrial != null && trial._activeInquiryCount == 0 && trial.signupInquiries) ? context.inquiryTrial : trial;
            if (_trial._activeInquiryCount > 0) {
                //row.append($('<div class="ui-grid-col-3"/>').text('xxxfragebogen'));
                var progressBar = $('<div id="trial_' + trial.id + '_pbar"/>').puiprogressbar({
                    labelTemplate: sprintf(context.inquiriesPbarTemplate, +_trial._savedInquiryCount, +_trial._activeInquiryCount),
                    value: Math.round((_trial._savedInquiryCount / _trial._activeInquiryCount) * 100.0)
                    //_postedInquiryCount
                });
                row.append($('<div class="ui-grid-col-5 ctsms-pbar-cell"/>').append(progressBar));
            } else {
                row.append($('<div class="ui-grid-col-5 ctsms-pbar-cell"/>'));
            }
            //if (signedUp) {
            //    row.append($('<div class="ui-grid-col-2"/>'));
            //} else {
            //    row.append($('<div class="ui-grid-col-2"/>'));
            //}
            var button = $('<button name="trial" type="submit" value="' + trial.id + '">' + (_trial._activeInquiryCount > 0 ? context.openInquiriesBtnLabel : context.signupBtnLabel) + '</button>').puibutton({
                icon: (_trial._activeInquiryCount > 0 ? 'fa-caret-right' : 'fa-user-plus'),
                iconPos: (_trial._activeInquiryCount > 0 ? 'right' : 'left')
            });
            //if ((context.enabledTrialId != null && context.enabledTrialId != trial.id) || (signedUp && _trial._activeInquiryCount == 0)) {
            if (signedUp && _trial._activeInquiryCount == 0) {
                button.puibutton('disable');
            }
            row.append($('<div class="ui-grid-col-7" style="text-align:right;"/>').append(button));
            grid.append(row);

            var panel = $('<div title="' + trial.name + '"/>').puipanel();
            panel.append(grid);

            return panel;
        },
        initContent: function(content) {
            var trial = context.trialStatusVar.trial;
            var iframeId = trial.id + '_signup_description';
            initIframe(iframeId, trial.signupDescription);
        }
    });

    $('#messages').puimessages();
    if (context.apiError != null) {
        setMessages('warn', context.apiError ); //{summary: 'Message Title', detail: context.apiError});
    }

    $('#done_btn').puibutton({
        //icon: 'fa-save'
        icon: 'fa-angle-double-right',
        iconPos: 'right'
    });

    $('#form').submit(function() {
        return _sanitizeForm(context);
    });
}

function _sanitizeForm(context) {
    //var result = true;
    //result = result && _sanitizeDatePicker('dob', 'dob_picker', true);
    //return result;
    showWaitDlg();

    //_sanitizeDatePicker('dob_picker', 'dob');
    return true;
}