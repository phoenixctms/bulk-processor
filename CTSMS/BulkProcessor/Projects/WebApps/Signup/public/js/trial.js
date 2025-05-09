
function initPrimeUI(context) {

    context.trialsPerPage = 5;
    context.trialsPerRow = 1;
    
    $('#trial_search').puiinputtext();
    $('#trial_search').puitooltip({
        my: 'left bottom',
        at: 'left top',
        content: context.trialSearchTooltip
    });    

    $("#trials").puidatagrid({
        header: context.trialsGridHeader,
        emptyMessage: context.trialsGridEmptyMessage,
        paginator: {
            rows: context.trialsPerPage,
            page: +context.trialPage
        },
        lazy: true,
        columns: context.trialsPerRow,
        datasource: function(callback, ui, updateUi) {
            $.ajax({

                url: context.uriBase + '/trials',
                data: { rows: ui.rows, first: ui.first, signupDescription:  $('#trial_search').val() },

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

            var grid = $('<div class="ui-grid"/>');

            var row = $('<div class="ui-grid-row"/>');
            var iframeId = trial.id + '_signup_description';
            row.append($('<div class="ui-grid-col-12 ui-widget ui-widget-content ui-corner-all ' + (selected ? 'ui-shadow ' : '') + 'ctsms-signup-description"/>').append(createIframe(iframeId, trial.signupDescription)));
            grid.append(row);

            row = $('<div class="ui-grid-row"/>');
            var _trial = (context.inquiryTrial != null && trial._activeInquiryCount == 0 && trial.signupInquiries) ? context.inquiryTrial : trial;
            if (_trial._activeInquiryCount > 0) {

                var progressBar = $('<div id="trial_' + trial.id + '_pbar"/>').puiprogressbar({
                    labelTemplate: sprintf(context.inquiriesPbarTemplate, +_trial._savedInquiryCount, +_trial._activeInquiryCount),
                    value: Math.round((_trial._savedInquiryCount / _trial._activeInquiryCount) * 100.0)

                });
                row.append($('<div class="ui-grid-col-5 ctsms-pbar-cell"/>').append(progressBar));
            } else {
                row.append($('<div class="ui-grid-col-5 ctsms-pbar-cell"/>'));
            }

            var button = $('<button name="trial" type="submit" value="' + trial.id + '">' + (_trial._activeInquiryCount > 0 ? context.openInquiriesBtnLabel : context.signupBtnLabel) + '</button>').puibutton({
                icon: (_trial._activeInquiryCount > 0 ? 'fa-caret-right' : 'fa-user-plus'),
                iconPos: (_trial._activeInquiryCount > 0 ? 'right' : 'left')
            });

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
    
    $('#trial_search').on('change', function(event) {
        //$("#trials").puidatagrid('paginate');
    }).on('keyup', delay(function() {
            $("#trials").puidatagrid('paginate');
        }, 300)
    );

    $('#messages').puimessages();
    if (context.apiError != null) {
        setMessages('warn', context.apiError );
    }

    $('#done_btn').puibutton({
        icon: 'fa-angle-double-right',
        iconPos: 'right'
    });

    $('#form').submit(function() {
        return _sanitizeForm(context);
    });
}

function _sanitizeForm(context) {

    showWaitDlg();
    return true;

}